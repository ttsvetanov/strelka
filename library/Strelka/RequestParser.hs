{-|
DSL for parsing the request.
-}
module Strelka.RequestParser
(
  RequestParser,
  -- * Errors
  fail,
  liftEither,
  liftMaybe,
  unliftEither,
  -- * Path Segments
  consumeSegment,
  consumeSegmentWithParser,
  consumeSegmentIfIs,
  ensureThatNoSegmentsIsLeft,
  -- * Params
  getParam,
  -- * Methods
  getMethod,
  ensureThatMethodIs,
  ensureThatMethodIsGet,
  ensureThatMethodIsPost,
  ensureThatMethodIsPut,
  ensureThatMethodIsDelete,
  ensureThatMethodIsHead,
  ensureThatMethodIsTrace,
  -- * Headers
  getHeader,
  ensureThatAccepts,
  ensureThatAcceptsText,
  ensureThatAcceptsHTML,
  ensureThatAcceptsJSON,
  checkIfAccepts,
  getAuthorization,
  -- * Body Consumption
  consumeBody,
)
where

import Strelka.Prelude hiding (fail)
import Strelka.Core.Model
import qualified Data.ByteString.Lazy as B
import qualified Data.ByteString.Lazy.Builder as C
import qualified Data.Text as E
import qualified Data.Text.Lazy as L
import qualified Data.Text.Lazy.Builder as M
import qualified Data.Attoparsec.ByteString as F
import qualified Data.Attoparsec.Text as Q
import qualified Data.HashMap.Strict as G
import qualified Network.HTTP.Media as K
import qualified Strelka.Core.RequestParser as A
import qualified Strelka.RequestBodyConsumer as P
import qualified Strelka.HTTPAuthorizationParser as D


{-|
Parser of an HTTP request.
Analyzes its meta information, consumes the path segments and the body.
-}
type RequestParser =
  A.RequestParser


-- * Errors
-------------------------

{-|
Fail with a text message.
-}
fail :: Monad m => Text -> RequestParser m a
fail message =
  A.RequestParser $
  lift $
  lift $
  ExceptT $
  return $
  Left $
  message

{-|
Lift Either, interpreting Left as a failure.
-}
liftEither :: Monad m => Either Text a -> RequestParser m a
liftEither =
  A.RequestParser .
  lift .
  lift .
  ExceptT .
  return

{-|
Lift Maybe, interpreting Nothing as a failure.
-}
liftMaybe :: Monad m => Maybe a -> RequestParser m a
liftMaybe =
  liftEither .
  maybe (Left "Unexpected Nothing") Right

{-|
Try a parser, extracting the error as Either.
-}
unliftEither :: Monad m => RequestParser m a -> RequestParser m (Either Text a)
unliftEither =
  tryError


-- * Path Segments
-------------------------

{-|
Consume the next segment of the path.
-}
consumeSegment :: Monad m => RequestParser m Text
consumeSegment =
  A.RequestParser $
  lift $
  StateT $
  \case
    PathSegment segmentText : segmentsTail ->
      return (segmentText, segmentsTail)
    _ ->
      ExceptT (return (Left "No segments left"))

{-|
Consume the next segment of the path with Attoparsec parser.
-}
consumeSegmentWithParser :: Monad m => Q.Parser a -> RequestParser m a
consumeSegmentWithParser parser =
  consumeSegment >>= liftEither . first E.pack . Q.parseOnly parser

{-|
Consume the next segment if it matches the provided value and fail otherwise.
-}
consumeSegmentIfIs :: Monad m => Text -> RequestParser m ()
consumeSegmentIfIs expectedSegment =
  do
    segment <- consumeSegment
    guard (segment == expectedSegment)

{-|
Fail if there's any path segments left unconsumed.
-}
ensureThatNoSegmentsIsLeft :: Monad m => RequestParser m ()
ensureThatNoSegmentsIsLeft =
  A.RequestParser (lift (gets null)) >>= guard


-- * Params
-------------------------

{-|
Get a parameter\'s value by its name, failing if the parameter is not present. 

@Maybe@ encodes whether a value was specified at all, i.e. @?name=value@ vs @?name@.
-}
getParam :: Monad m => ByteString -> RequestParser m (Maybe ByteString)
getParam name =
  do
    Request _ _ params _ _ <- A.RequestParser ask
    liftMaybe (liftM (\(ParamValue value) -> value) (G.lookup (ParamName name) params))


-- * Methods
-------------------------

{-|
Get the request method.
-}
getMethod :: Monad m => RequestParser m ByteString
getMethod =
  do
    Request (Method method) _ _ _ _ <- A.RequestParser ask
    return method

{-|
Ensure that the method matches the provided value __in lower-case__.
-}
ensureThatMethodIs :: Monad m => ByteString -> RequestParser m ()
ensureThatMethodIs expectedMethod =
  do
    method <- getMethod
    guard (expectedMethod == method)

{-|
Same as @'ensureThatMethodIs' "get"@.
-}
ensureThatMethodIsGet :: Monad m => RequestParser m ()
ensureThatMethodIsGet =
  ensureThatMethodIs "get"

{-|
Same as @'ensureThatMethodIs' "post"@.
-}
ensureThatMethodIsPost :: Monad m => RequestParser m ()
ensureThatMethodIsPost =
  ensureThatMethodIs "post"

{-|
Same as @'ensureThatMethodIs' "put"@.
-}
ensureThatMethodIsPut :: Monad m => RequestParser m ()
ensureThatMethodIsPut =
  ensureThatMethodIs "put"

{-|
Same as @'ensureThatMethodIs' "delete"@.
-}
ensureThatMethodIsDelete :: Monad m => RequestParser m ()
ensureThatMethodIsDelete =
  ensureThatMethodIs "delete"

{-|
Same as @'ensureThatMethodIs' "head"@.
-}
ensureThatMethodIsHead :: Monad m => RequestParser m ()
ensureThatMethodIsHead =
  ensureThatMethodIs "head"

{-|
Same as @'ensureThatMethodIs' "trace"@.
-}
ensureThatMethodIsTrace :: Monad m => RequestParser m ()
ensureThatMethodIsTrace =
  ensureThatMethodIs "trace"


-- * Headers
-------------------------

{-|
Lookup a header by name __in lower-case__.
-}
getHeader :: Monad m => ByteString -> RequestParser m ByteString
getHeader name =
  do
    Request _ _ _ headers _ <- A.RequestParser ask
    liftMaybe (liftM (\(HeaderValue value) -> value) (G.lookup (HeaderName name) headers))

{-|
Ensure that the request provides an Accept header,
which includes the specified content type.
Content type must be __in lower-case__.
-}
ensureThatAccepts :: Monad m => ByteString -> RequestParser m ()
ensureThatAccepts contentType =
  checkIfAccepts contentType >>=
  liftEither . bool (Left ("Unacceptable content-type: " <> fromString (show contentType))) (Right ())

{-|
Same as @'ensureThatAccepts' "text/plain"@.
-}
ensureThatAcceptsText :: Monad m => RequestParser m ()
ensureThatAcceptsText =
  ensureThatAccepts "text/plain"

{-|
Same as @'ensureThatAccepts' "text/html"@.
-}
ensureThatAcceptsHTML :: Monad m => RequestParser m ()
ensureThatAcceptsHTML =
  ensureThatAccepts "text/html"

{-|
Same as @'ensureThatAccepts' "application/json"@.
-}
ensureThatAcceptsJSON :: Monad m => RequestParser m ()
ensureThatAcceptsJSON =
  ensureThatAccepts "application/json"

{-|
Check whether the request provides an Accept header,
which includes the specified content type.
Content type must be __in lower-case__.
-}
checkIfAccepts :: Monad m => ByteString -> RequestParser m Bool
checkIfAccepts contentType =
  liftM (isJust . K.matchAccept [contentType]) (getHeader "accept")

{-|
Parse the username and password from the basic authorization header.
-}
getAuthorization :: Monad m => RequestParser m (Text, Text)
getAuthorization =
  getHeader "authorization" >>= liftEither . D.basicCredentials


-- * Body Consumption
-------------------------

{-|
Consume the request body using the provided RequestBodyConsumer.

[NOTICE]
Since the body is consumed as a stream,
you can only consume it once regardless of the Alternative branching.
-}
consumeBody :: MonadIO m => P.RequestBodyConsumer a -> RequestParser m a
consumeBody (P.RequestBodyConsumer consume) =
  do
    Request _ _ _ _ (InputStream getChunk) <- A.RequestParser ask
    liftIO (consume getChunk)
