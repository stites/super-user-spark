module CompilerSpec where

import           Test.Hspec
import           Test.QuickCheck

import           Data.Either           (isLeft, isRight)
import           Data.List             (intercalate, isPrefixOf)
import           System.FilePath.Posix ((</>))

import           CoreTypes
--import           Compiler.TestUtils
import           Compiler
import           Compiler.Gen
import           Compiler.Internal
import           Compiler.TestUtils
import           Compiler.Types
import           Config
import           Parser.Types
import           TestUtils
import           Types
import           Utils

spec :: Spec
spec = parallel $ do
    singleCompileDecSpec
    precompileSpec
    compilerBlackBoxTests


precompileSpec :: Spec
precompileSpec = describe "pre-compilation" $ do
    cleanContentCheckSpec

cleanContentCheckSpec :: Spec
cleanContentCheckSpec = do
    let c = defaultConfig
    let run = runPreCompiler
    let validFp = arbitrary `suchThat` cleanBy cleanFilePathCheck

    describe "cleanCardCheck" $ do
        it "doesn't report any card with valid content and a valid name" $ do
            forAll (arbitrary `suchThat` cleanBy cleanCardNameCheck) $ \cn ->
              forAll (arbitrary `suchThat` cleanBy cleanDeclarationCheck) $ \cc ->
                Card cn cc `shouldSatisfy` cleanBy cleanCardCheck

    describe "cleanCardNameCheck" $ do
        pend

        it "doesn't report an emty card name" $ do
            "" `shouldSatisfy` cleanBy cleanCardNameCheck

        it "reports card names with newlines" $ do
            forAll (arbitrary `suchThat` containsNewlineCharacter) $ \s ->
                s `shouldNotSatisfy` cleanBy cleanCardNameCheck

    describe "cleanDeclarationCheck" $ do
        describe "Deploy" $ do
            it "doesn't report Deploy declarations with valid filepaths" $ do
                forAll validFp $ \src ->
                  forAll validFp $ \dst ->
                    forAll arbitrary $ \kind ->
                      Deploy src dst kind `shouldSatisfy` cleanBy cleanDeclarationCheck

            it "reports Deploy declarations with an invalid source" $ do
                forAll (arbitrary `suchThat` (not . cleanBy cleanFilePathCheck)) $ \src ->
                  forAll validFp $ \dst ->
                    forAll arbitrary $ \kind ->
                      Deploy src dst kind `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "reports Deploy declarations with an invalid destination" $ do
                forAll validFp $ \src ->
                  forAll (arbitrary `suchThat` (not . cleanBy cleanFilePathCheck)) $ \dst ->
                    forAll arbitrary $ \kind ->
                      Deploy src dst kind `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "SparkOff" $ do
            it "reports SparkOff declarations with an invalid card reference" $ do
                forAll (arbitrary `suchThat` (not . cleanBy cleanCardReferenceCheck)) $ \cr ->
                  SparkOff cr `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "doesn't report SparkOff declarations with a valid card reference" $ do
                forAll (arbitrary `suchThat` cleanBy cleanCardReferenceCheck) $ \cr ->
                  SparkOff cr `shouldSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "IntoDir" $ do
            it "reports IntoDir declarations with an invalid filepath" $ do
                forAll (arbitrary `suchThat` (not . cleanBy cleanFilePathCheck)) $ \fp ->
                  IntoDir fp `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "doesn't report IntoDir declarations with a valid filepath" $ do
                forAll (arbitrary `suchThat` cleanBy cleanFilePathCheck) $ \fp ->
                  IntoDir fp `shouldSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "OutofDir" $ do
            it "reports OutofDir declarations with an invalid filepath" $ do
                forAll (arbitrary `suchThat` (not . cleanBy cleanFilePathCheck)) $ \fp ->
                  OutofDir fp `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "doesn't report OutofDir declarations with a valid filepath" $ do
                forAll (arbitrary `suchThat` cleanBy cleanFilePathCheck) $ \fp ->
                  OutofDir fp `shouldSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "DeployKindOverride" $ do
            it "doesn't report any deployment kind override declarations" $ do
                forAll arbitrary $ \kind ->
                    DeployKindOverride kind `shouldSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "Alternatives" $ do
            it "reports alternatives declarations with as much as a single invalid filepath" $ do
                forAll (arbitrary `suchThat` (any $ not . cleanBy cleanFilePathCheck)) $ \fs ->
                    Alternatives fs `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "doesn't report alternatives declarations with valid filepaths" $ do
                forAll (arbitrary `suchThat` (all $ cleanBy cleanFilePathCheck)) $ \fs ->
                    Alternatives fs `shouldSatisfy` cleanBy cleanDeclarationCheck

            pend

        describe "Block" $ do
            it "reports block declarations with as much as a single invalid declaration inside" $ do
                forAll (arbitrary `suchThat` (any $ not . cleanBy cleanDeclarationCheck)) $ \ds ->
                    Block ds `shouldNotSatisfy` cleanBy cleanDeclarationCheck

            it "doesn't report any block declarations with valid declarations inside" $ do
                forAll (arbitrary `suchThat` (all $ cleanBy cleanDeclarationCheck)) $ \ds ->
                    Block ds `shouldSatisfy` cleanBy cleanDeclarationCheck


            pend

    describe "cleanCardReferenceCheck" $ do
        pend

    describe "cleanCardFileReferenceCheck" $ do
        pend

    describe "cleanCardNameReferenceCheck" $ do
        pend


    describe "cleanFilePathCheck" $ do
        it "reports empty an filepath" $ do
            filePathDirty []

        let nonNull = arbitrary `suchThat` (not . null)
        it "reports filepaths with newlines" $ do
            forAll (nonNull `suchThat` containsNewlineCharacter) filePathDirty

        let withoutNewlines = nonNull `suchThat` (not . containsNewlineCharacter)
        it "reports filepaths with multiple consequtive slashes" $ do
            once $ forAll (withoutNewlines `suchThat` containsMultipleConsequtiveSlashes) filePathDirty

        let c = filePathClean
        it "doesn't report these valid filepaths" $ do
            c "noextension"
            c ".bashrc"
            c "file.txt"
            c "Some file with spaces.doc"
            c "some/relative/filepath.file"


defaultCompilerState :: CompilerState
defaultCompilerState = CompilerState
    { state_deployment_kind_override = Nothing
    , state_into = ""
    , state_outof_prefix = []
    }

singleCompileDecSpec :: Spec
singleCompileDecSpec = describe "compileDec" $ do
    let s = defaultCompilerState
    let c = defaultConfig
    let sc = singleShouldCompileTo c s
    let sf = singleShouldFail c s

    let nonNull = arbitrary `suchThat` (not . null)
    let validFilePath = nonNull `suchThat` (not . containsNewlineCharacter)
    let easyFilePath = validFilePath `suchThat` (not . isPrefixOf ".")

    describe "Deploy" $ do
        it "uses the exact right text in source and destination when given valid filepaths without a leading dot" $ do
            forAll easyFilePath $ \from ->
                forAll easyFilePath $ \to ->
                    sc (Deploy from to Nothing) (Put [from] to LinkDeployment)

        it "handles filepaths with a leading dot correctly" $ do
            pending

        it "figures out the correct paths in these cases with default config and initial state" $ do
            let d = (Deploy "from" "to" $ Just LinkDeployment)
            sc d (Put ["from"] "to" LinkDeployment)

        it "uses the alternates correctly" $ do
            pending

        it "uses the into's correctly" $ do
            pending

        it "uses the outof's correctly" $ do
            pending

        pend

    describe "SparkOff" $ do
        it "adds a single card file reference to the list of cards to spark later" $ do
            forAll validFilePath $ \f ->
                let cr = CardFile $ CardFileReference f Nothing
                    d = SparkOff cr
                in compileSingleDec d s c `shouldBe` Right (s, ([], [cr]))

        it "adds any card reference to the list" $ do
            pending

        pend

    describe "IntoDir" $ do
        pend

    describe "OutofDir" $ do
        pend

    describe "DeployKindOverride" $ do
        pend

    describe "Block" $ do
        it "uses a separate scope for its sub-compilation" $ do
            pendingWith "first we need an arbitrary instance for declarations"

    describe "Alternatives" $ do
        it "adds an alternatives prefix to the outof prefix in the compiler state" $ do
            forAll (listOf validFilePath) $ \fps ->
                shouldResultInState c s (Alternatives fps) $ s { state_outof_prefix = [Alts fps] }

        pend


compilerBlackBoxTests :: Spec
compilerBlackBoxTests = do

    let tr = "test_resources"
    describe "Correct succesful compile examples" $ do
        let dirs = map (tr </>) ["shouldCompile"]
        forFileInDirss dirs $ concerningContents $ \f contents -> do
            it f $ do
                r <- flip runReaderT defaultConfig $ runExceptT $ compileJob $ CardFileReference f Nothing
                r `shouldSatisfy` isRight

    describe "Correct unsuccesfull compile examples" $ do
        let dirs = map (tr </>) ["shouldNotParse", "shouldNotCompile"]
        forFileInDirss dirs $ concerningContents $ \f contents -> do
            it f $ do
                r <- flip runReaderT defaultConfig $ runExceptT $ compileJob $ CardFileReference f Nothing
                r `shouldSatisfy` isLeft

