{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TemplateHaskell #-}

module SuperUserSpark.DeployerSpec where

import qualified Prelude as P (writeFile)
import TestImport

import Data.Either (isLeft)
import Data.Maybe (isNothing)

import System.Directory
       hiding (createDirectoryIfMissing, removeFile)
import System.Posix.Files

import SuperUserSpark.Bake.Types
import SuperUserSpark.Check.Internal
import SuperUserSpark.Check.Types
import SuperUserSpark.Deployer
import SuperUserSpark.Deployer.Gen ()
import SuperUserSpark.Deployer.Internal
import SuperUserSpark.Deployer.Types
import SuperUserSpark.OptParse.Gen ()
import SuperUserSpark.Parser.Gen
import SuperUserSpark.Utils

spec :: Spec
spec = do
    instanceSpec
    deployerSpec
    cleanSpec
    deploymentSpec

instanceSpec :: Spec
instanceSpec =
    parallel $ do
        eqSpec @DeployAssignment
        genValidSpec @DeployAssignment
        eqSpec @DeploySettings
        genValidSpec @DeploySettings
        eqSpec @DeployError
        genValidSpec @DeployError
        eqSpec @PreDeployment
        genValidSpec @PreDeployment

deployerSpec :: Spec
deployerSpec =
    parallel $ do
        describe "defaultDeploySettings" $
            it "is valid" $ isValid defaultDeploySettings
        describe "formatDeployError" $ do
            it "only ever produces valid strings" $
                producesValid formatDeployError

cleanSpec :: Spec
cleanSpec = do
    here <- runIO getCurrentDir
    let sandbox = here </> $(mkRelDir "test_sandbox")
    let setup = ensureDir sandbox
    let teardown = removeDirRecur sandbox
    let clean :: DeploySettings -> CleanupInstruction -> IO ()
        clean sets ci =
            runReaderT (runExceptT $ performClean ci) sets `shouldReturn`
            Right ()
    beforeAll_ setup $
        afterAll_ teardown $ do
            describe "performClean" $ do
                it "doesn't remove this file if that's not in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceFiles = False}
                    withCurrentDir sandbox $ do
                        let file = sandbox </> $(mkRelFile "test.txt")
                        let fp = AbsP file
                        writeFile file "This is a test"
                        diagnoseFp fp `shouldReturn` IsFile
                        clean c $ CleanFile file
                        diagnoseFp fp `shouldReturn` IsFile
                        removeFile file
                        diagnoseFp fp `shouldReturn` Nonexistent
                it "removes this file if that's in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceFiles = True}
                    withCurrentDir sandbox $ do
                        let file = sandbox </> $(mkRelFile "test.txt")
                        let fp = AbsP file
                        writeFile file "This is a test"
                        diagnoseFp fp `shouldReturn` IsFile
                        clean c $ CleanFile file
                        diagnoseFp fp `shouldReturn` Nonexistent
                it "doesn't remove this directory if that's not in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceDirectories = False}
                    withCurrentDir sandbox $ do
                        let dir = sandbox </> $(mkRelDir "testdirectory")
                        let dirf =
                                AbsP $ sandbox </> $(mkRelFile "testdirectory")
                        ensureDir dir
                        diagnoseFp dirf `shouldReturn` IsDirectory
                        clean c $ CleanDirectory dir
                        diagnoseFp dirf `shouldReturn` IsDirectory
                        removeDirRecur dir
                        diagnoseFp dirf `shouldReturn` Nonexistent
                it "removes this directory if that's in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceDirectories = True}
                    withCurrentDir sandbox $ do
                        let dir = sandbox </> $(mkRelDir "testdirectory")
                        let dirf =
                                AbsP $ sandbox </> $(mkRelFile "testdirectory")
                        ensureDir dir
                        diagnoseFp dirf `shouldReturn` IsDirectory
                        clean c $ CleanDirectory dir
                        diagnoseFp dirf `shouldReturn` Nonexistent
                it "doesn't remove this link if that's not in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceLinks = False}
                    withCurrentDir sandbox $ do
                        let link_ = sandbox </> $(mkRelFile "testlink")
                        let link_' = AbsP link_
                        let file_ = sandbox </> $(mkRelFile "testfile")
                        let file_' = AbsP file_
                        writeFile file_ "This is a test"
                        createSymbolicLink (toFilePath file_) (toFilePath link_)
                        diagnoseFp link_' `shouldReturn` IsLinkTo file_'
                        clean c $ CleanLink link_
                        diagnoseFp link_' `shouldReturn` IsLinkTo file_'
                        removeLink $ toFilePath link_
                        diagnoseFp link_' `shouldReturn` Nonexistent
                        removeFile file_
                        diagnoseFp file_' `shouldReturn` Nonexistent
                it
                    "removes this link with an existent source if that's in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceLinks = True}
                    withCurrentDir sandbox $ do
                        let link_ = sandbox </> $(mkRelFile "testlink")
                        let link_' = AbsP link_
                        let file_ = sandbox </> $(mkRelFile "testfile")
                        let file_' = AbsP file_
                        writeFile file_ "This is a test"
                        createSymbolicLink (toFilePath file_) (toFilePath link_)
                        diagnoseFp link_' `shouldReturn` IsLinkTo file_'
                        clean c $ CleanLink link_
                        diagnoseFp link_' `shouldReturn` Nonexistent
                        diagnoseFp file_' `shouldReturn` IsFile
                        removeFile file_
                        diagnoseFp file_' `shouldReturn` Nonexistent
                it
                    "removes this link with a nonexistent source if that's in the config" $ do
                    let c =
                            defaultDeploySettings
                            {deploySetsReplaceLinks = True}
                    withCurrentDir sandbox $ do
                        let link_ = sandbox </> $(mkRelFile "testlink")
                        let link_' = AbsP link_
                        let file_ = sandbox </> $(mkRelFile "testfile")
                        let file_' = AbsP file_
                        createSymbolicLink (toFilePath file_) (toFilePath link_)
                        diagnoseFp link_' `shouldReturn` IsLinkTo file_'
                        diagnoseFp file_' `shouldReturn` Nonexistent
                        clean c $ CleanLink link_
                        diagnoseFp link_' `shouldReturn` Nonexistent
                        diagnoseFp file_' `shouldReturn` Nonexistent

deploymentSpec :: Spec
deploymentSpec = do
    here <- runIO $ getCurrentDir
    let sandbox = here </> $(mkRelDir "test_sandbox")
    let setup = ensureDir sandbox
    let teardown = removeDirRecur sandbox
    beforeAll_ setup $
        afterAll_ teardown $ do
            describe "copy" $ do
                it "succcesfully copies this file" $ do
                    withCurrentDir sandbox $ do
                        let src = sandbox </> $(mkRelFile "testfile")
                        let src' = AbsP src
                        let dst = sandbox </> $(mkRelFile "testcopy")
                        let dst' = AbsP dst
                        writeFile src "This is a file."
                        diagnoseFp src' `shouldReturn` IsFile
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        -- Under test
                        copy src' dst'
                        diagnoseFp src' `shouldReturn` IsFile
                        diagnoseFp dst' `shouldReturn` IsFile
                        dsrc <- diagnose src'
                        ddst <- diagnose dst'
                        diagnosedHashDigest ddst `shouldBe`
                            diagnosedHashDigest dsrc
                        removeFile src
                        removeFile dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
                it "succcesfully copies this directory" $ do
                    withCurrentDir sandbox $ do
                        let src = sandbox </> $(mkRelDir "testdir")
                        let src' = AbsP $ sandbox </> $(mkRelFile "testdir")
                        let dst = sandbox </> $(mkRelDir "testcopy")
                        let dst' = AbsP $ sandbox </> $(mkRelFile "testcopy")
                        ensureDir src
                        diagnoseFp src' `shouldReturn` IsDirectory
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        -- Under test
                        copy src' dst'
                        diagnoseFp src' `shouldReturn` IsDirectory
                        diagnoseFp dst' `shouldReturn` IsDirectory
                        dsrc <- diagnose src'
                        ddst <- diagnose dst'
                        diagnosedHashDigest ddst `shouldBe`
                            diagnosedHashDigest dsrc
                        removeDirRecur src
                        removeDirRecur dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
            describe "link" $ do
                it "successfully links this file" $ do
                    withCurrentDir sandbox $ do
                        let src = sandbox </> $(mkRelFile "testfile")
                        let src' = AbsP src
                        let dst = sandbox </> $(mkRelFile "testlink")
                        let dst' = AbsP dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        writeFile src "This is a test."
                        diagnoseFp src' `shouldReturn` IsFile
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        -- Under test
                        link src' dst'
                        diagnoseFp src' `shouldReturn` IsFile
                        diagnoseFp dst' `shouldReturn` IsLinkTo src'
                        removeFile src
                        removeLink $ toFilePath dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
                it "successfully links this directory" $ do
                    withCurrentDir sandbox $ do
                        let src = sandbox </> $(mkRelDir "testdir")
                        let src' = AbsP $ sandbox </> $(mkRelFile "testdir")
                        let dst = sandbox </> $(mkRelFile "testlink")
                        let dst' = AbsP dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        ensureDir src
                        diagnoseFp src' `shouldReturn` IsDirectory
                        diagnoseFp dst' `shouldReturn` Nonexistent
                        -- Under test
                        link src' dst'
                        diagnoseFp src' `shouldReturn` IsDirectory
                        diagnoseFp dst' `shouldReturn` IsLinkTo src'
                        removeDirRecur src
                        removeLink $ toFilePath dst
                        diagnoseFp src' `shouldReturn` Nonexistent
                        diagnoseFp dst' `shouldReturn` Nonexistent
