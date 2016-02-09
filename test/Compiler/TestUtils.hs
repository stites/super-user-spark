module Compiler.TestUtils where

import           Compiler.Internal
import           Compiler.Types
import           Data.Either       (isLeft, isRight)
import           Language.Types
import           Test.Hspec
import           Types

runPreCompiler :: Precompiler () -> [PrecompileError]
runPreCompiler pc = runIdentity $ execWriterT pc

cleanBy :: (a -> Precompiler ()) -> a -> Bool
cleanBy func a = null $ runPreCompiler $ func a

declarationClean :: Declaration -> IO ()
declarationClean d = d `shouldSatisfy` cleanBy cleanDeclarationCheck

declarationDirty :: Declaration -> IO ()
declarationDirty d = d `shouldNotSatisfy` cleanBy cleanDeclarationCheck

filePathDirty :: FilePath -> IO ()
filePathDirty fp = fp `shouldNotSatisfy` cleanBy cleanFilePathCheck

filePathClean :: FilePath -> IO ()
filePathClean fp = fp `shouldSatisfy` cleanBy cleanFilePathCheck

runPureCompiler :: SparkConfig -> PureCompiler a -> Either CompileError a
runPureCompiler c func = runIdentity $ runReaderT (runExceptT func) c

runInternalCompiler
     :: [Declaration]
    -> CompilerState
    -> SparkConfig
    -> Either CompileError (CompilerState, ([Deployment], [CardReference]))
runInternalCompiler ds s c = runPureCompiler c $ runWriterT $ execStateT (compileDecs ds) s

compileSingleDec
    :: Declaration
    -> CompilerState
    -> SparkConfig
    -> Either CompileError (CompilerState, ([Deployment], [CardReference]))
compileSingleDec d = runInternalCompiler [d]


compilationShouldSucceed
    :: [Declaration]
    -> CompilerState
    -> SparkConfig
    -> IO ()
compilationShouldSucceed ds s c = runInternalCompiler ds s c `shouldSatisfy` isRight

compilationShouldFail
    :: [Declaration]
    -> CompilerState
    -> SparkConfig
    -> IO ()
compilationShouldFail ds s c = runInternalCompiler ds s c `shouldSatisfy` isLeft

singleShouldFail
    :: SparkConfig
    -> CompilerState
    -> Declaration
    -> IO ()
singleShouldFail c s d = compilationShouldFail [d] s c

shouldCompileTo
    :: SparkConfig
    -> CompilerState
    -> [Declaration]
    -> [Deployment]
    -> IO ()
shouldCompileTo c s ds eds = do
    compilationShouldSucceed ds s c
    let Right (_, (ads, crs)) = runInternalCompiler ds s c
    ads `shouldBe` eds
    crs `shouldSatisfy` null

singleShouldCompileTo
    :: SparkConfig
    -> CompilerState
    -> Declaration
    -> Deployment
    -> IO ()
singleShouldCompileTo c s d eds = shouldCompileTo c s [d] [eds]

shouldResultInState
    :: SparkConfig
    -> CompilerState
    -> Declaration
    -> CompilerState
    -> IO ()
shouldResultInState c s d es = do
    compilationShouldSucceed [d] s c
    let Right (as, _) = runInternalCompiler [d] s c
    as `shouldBe` es



-- Filepath utils
containsNewlineCharacter :: String -> Bool
containsNewlineCharacter f = any (\c -> elem c f) ['\n', '\r']