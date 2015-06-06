module Deployer where

import           System.Directory   (copyFile)
import           System.Posix.Files (createSymbolicLink)

import           Types

deploy :: [Deployment] -> IO ()
deploy dp = sequence_ $ map oneDeployment dp

oneDeployment :: Deployment -> IO ()
oneDeployment (Link src dst) = createSymbolicLink src dst
oneDeployment (Copy src dst) = copyFile src dst

formatDeployments :: [Deployment] -> String
formatDeployments = unlines . map formatDeployment

formatDeployment :: Deployment -> String
formatDeployment (Link src dst) = unwords [src, "l->", dst]
formatDeployment (Copy src dst) = unwords [src, "c->", dst]

