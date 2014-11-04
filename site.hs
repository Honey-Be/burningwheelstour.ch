--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Control.Applicative ((<$>))
import           Control.Applicative ((<$>), (<*>))
import           Control.Monad       (filterM, mapM)
import           Data.List           (nub, partition, sort)
import qualified Data.Map            as M
import           Data.Monoid         (mconcat)
import           Data.Time           (UTCTime, toGregorian, utctDay)
import           Hakyll
import           System.FilePath     (dropExtension, joinPath, splitPath)
import           System.Locale       (defaultTimeLocale)
import           System.Process      (rawSystem)


--------------------------------------------------------------------------------
main :: IO ()
main = hakyll $ do
    ----------------------------------------------------------------------------
    match "js/*.js" $ do
        route   idRoute
        compile copyFileCompiler


    ----------------------------------------------------------------------------
    -- Regular images
    match "images/**.png" $ do
        route   idRoute
        compile copyFileCompiler


    ----------------------------------------------------------------------------
    -- SVG images
    match "images/*.svg" $ do
        route   $ setExtension "png"
        compile $ do
            i         <- toFilePath <$> getUnderlying
            TmpFile o <- newTmpFile "out.png"
            _         <- unsafeCompiler $
                            rawSystem "inkscape" ["-z", "-e", o, i]
            makeItem $ TmpFile o


    ----------------------------------------------------------------------------
    -- .less files
    allLessFiles <- makePatternDependency "style/*.less"
    match "style/main.less" $ rulesExtraDependencies [allLessFiles] $ do
        route   $ setExtension "css"
        compile $ do
            i         <- toFilePath <$> getUnderlying
            TmpFile o <- newTmpFile "out.css"
            _         <- unsafeCompiler $ rawSystem "lessc" [i, o]
            makeItem $ TmpFile o
    match "style/*.less" $ compile $ makeItem ()


    ----------------------------------------------------------------------------
    -- Page per event
    match "events/*.html" $ do
        -- No output yet
        route   $ indexRoute
        compile $
            getResourceBody                                        >>=
            loadAndApplyTemplate "templates/event.html"   eventCtx >>=
            loadAndApplyTemplate "templates/default.html" eventCtx >>=
            prettifyIndexRoutes                                    >>=
            relativizeUrls


    ----------------------------------------------------------------------------
    -- Pages
    match "*.html" $ do
        route   $ indexRoute
        compile $
            getResourceBody                                       >>=
            applyAsTemplate pageCtx                               >>=
            loadAndApplyTemplate "templates/default.html" pageCtx >>=
            prettifyIndexRoutes                                   >>=
            relativizeUrls


    ----------------------------------------------------------------------------
    -- Templates
    match "templates/*.html" $ compile templateCompiler


--------------------------------------------------------------------------------
indexRoute :: Routes
indexRoute = customRoute $ \identifier ->
    let path  = splitPath (toFilePath identifier)
        names = case dropExtension (last path) of
            "index" -> ["index.html"]
            n       -> [n, "index.html"]
    in joinPath (init path ++ names)


--------------------------------------------------------------------------------
prettifyIndexRoutes :: Item String -> Compiler (Item String)
prettifyIndexRoutes = return . fmap (withUrls prettify)
  where
    prettify []               = []
    prettify url@(x : xs)
        | "index.html" == url = []
        | otherwise           = x : prettify xs


--------------------------------------------------------------------------------
eventCtx :: Context String
eventCtx = mconcat
    [ field "year" $
        fmap (show . getYear) . getItemUTC defaultTimeLocale . itemIdentifier
    , functionField "activeClass" $ \[p] _ -> do
        return $ case fromFilePath p of
            "events.html" -> "active"
            _             -> "inactive"
    , defaultContext
    ]


--------------------------------------------------------------------------------
pageCtx :: Context String
pageCtx = mconcat
    [ listField "years" yearCtx $ do
        (_, archived) <- findEvents
        years         <-
            mapM (fmap getYear . getItemUTC defaultTimeLocale) archived
        mapM makeItem $ nub $ reverse $ sort years
    , listField "events" eventCtx $ do
        (current, _) <- findEvents
        chronological =<< mapM load current
    , functionField "activeClass" $ \[p] _ -> do
        underlying <- getUnderlying
        return $ if fromFilePath p == underlying then "active" else "inactive"
    , defaultContext
    ]
  where
    yearCtx :: Context Integer
    yearCtx = mconcat
        [ field "year" $ return . show . itemBody
        , listFieldWith "events" eventCtx $ \yearItem -> do
            (_, archived) <- findEvents
            thisYear      <- filterM
                (fmap ((== itemBody yearItem) . getYear) .
                    getItemUTC defaultTimeLocale)
                archived
            chronological =<< mapM load thisYear
        ]


--------------------------------------------------------------------------------
findEvents :: Compiler ([Identifier], [Identifier])  -- current, archived
findEvents = do
    metadatas <- getAllMetadata "events/*.html"
    let (current, archived) =
            partition (\(_, md) -> M.lookup "archived" md /= Just "true") $
            metadatas
    return (map fst current, map fst archived)


--------------------------------------------------------------------------------
getYear :: UTCTime -> Integer
getYear utct = let (year, _, _) = toGregorian (utctDay utct) in year
