{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Control.Monad (forM, when, void)
import Data.Aeson (FromJSON(..), ToJSON(..), Value, eitherDecode, encode, object, (.=))
import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Data.HashMap.Strict as HashMap
import Data.List (intercalate)
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import Data.Text (Text, unpack)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Calendar (Day, toGregorian)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import GHC.Generics (Generic)
import Network.HTTP.Simple
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs, getEnv, lookupEnv)
import System.FilePath ((</>), takeDirectory)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Printf (printf)

-- TMDB API Configuration
apiBaseUrl :: String
apiBaseUrl = "https://api.themoviedb.org/3"

imageBaseUrl :: String
imageBaseUrl = "https://image.tmdb.org/t/p/w500"

-- Data Types
data Category = Category
  { catId :: String,
    catName :: String,
    catEndpoint :: String,
    catParams :: [(String, String)],
    catLimit :: Int
  }
  deriving (Show)

data TMDBMovie = TMDBMovie
  { tmdbId :: Int,
    tmdbTitle :: Maybe String,
    tmdbName :: Maybe String,
    tmdbPosterPath :: Maybe String,
    tmdbBackdropPath :: Maybe String,
    tmdbReleaseDate :: Maybe String,
    tmdbFirstAirDate :: Maybe String,
    tmdbVoteAverage :: Maybe Float,
    tmdbOverview :: Maybe String,
    tmdbGenreIds :: Maybe [Int]
  }
  deriving (Show, Generic)

data TMDBCredit = TMDBCredit
  { tmdbCreditId :: String,
    tmdbCast :: [TMDBCastMember],
    tmdbCrew :: [TMDBCrewMember]
  }
  deriving (Show, Generic)

data TMDBCastMember = TMDBCastMember
  { tmdbCastId :: Int,
    tmdbCastCharacter :: String,
    tmdbCastCreditId :: String,
    tmdbCastGender :: Maybe Int,
    tmdbCastPersonId :: Int,
    tmdbCastName :: String,
    tmdbCastOrder :: Int,
    tmdbCastProfilePath :: Maybe String
  }
  deriving (Show, Generic)

data TMDBCrewMember = TMDBCrewMember
  { tmdbCrewCreditId :: String,
    tmdbCrewDepartment :: String,
    tmdbCrewGender :: Maybe Int,
    tmdbCrewPersonId :: Int,
    tmdbCrewJob :: String,
    tmdbCrewName :: String,
    tmdbCrewProfilePath :: Maybe String
  }
  deriving (Show, Generic)

data MediaItem = MediaItem
  { mediaId :: String,
    mediaTitle :: String,
    mediaType :: String,
    mediaImageUrl :: String,
    mediaYear :: Int,
    mediaRating :: Float,
    mediaDescription :: String,
    mediaBackdropUrl :: Maybe String,
    mediaGenres :: [String],
    mediaCast :: [CastMember],
    mediaDirectors :: [CrewMember]
  }
  deriving (Show, Generic)

data CastMember = CastMember
  { castId :: String,
    castName :: String,
    castCharacter :: String,
    castProfileUrl :: Maybe String,
    castOrder :: Int
  }
  deriving (Show, Generic)

data CrewMember = CrewMember
  { crewId :: String,
    crewName :: String,
    crewJob :: String,
    crewDepartment :: String,
    crewProfileUrl :: Maybe String
  }
  deriving (Show, Generic)

data Genre = Genre
  { genreId :: Int,
    genreName :: String
  }
  deriving (Show, Generic)

data GenreResponse = GenreResponse
  { genres :: [Genre]
  }
  deriving (Show, Generic)

data TMDBResponse = TMDBResponse
  { results :: [TMDBMovie]
  }
  deriving (Show, Generic)

data CategoryOutput = CategoryOutput
  { outId :: String,
    outName :: String,
    outItems :: [MediaItem]
  }
  deriving (Show, Generic)

data OutputData = OutputData
  { categories :: [CategoryOutput]
  }
  deriving (Show, Generic)

-- JSON instances
instance FromJSON TMDBMovie where
  parseJSON = A.withObject "TMDBMovie" $ \v -> do
    tmdbId <- v A..: "id"
    tmdbTitle <- v A..:? "title"
    tmdbName <- v A..:? "name"
    tmdbPosterPath <- v A..:? "poster_path"
    tmdbBackdropPath <- v A..:? "backdrop_path"
    tmdbReleaseDate <- v A..:? "release_date"
    tmdbFirstAirDate <- v A..:? "first_air_date"
    tmdbVoteAverage <- v A..:? "vote_average"
    tmdbOverview <- v A..:? "overview"
    tmdbGenreIds <- v A..:? "genre_ids"
    return TMDBMovie {..}

instance FromJSON TMDBCredit where
  parseJSON = A.withObject "TMDBCredit" $ \v -> do
    -- Parse the ID field directly as a string to avoid type issues
    movieId <- v A..: "id"
    tmdbCast <- v A..: "cast"
    tmdbCrew <- v A..: "crew"
    -- Convert to string explicitly, working around type inference issues
    let tmdbCreditId = case movieId of
                         A.Number n -> show (round n :: Int)
                         A.String s -> T.unpack s
                         _ -> "unknown"
    return TMDBCredit {..}

instance FromJSON TMDBCastMember where
  parseJSON = A.withObject "TMDBCastMember" $ \v -> do
    tmdbCastId <- v A..: "cast_id"
    tmdbCastCharacter <- v A..: "character"
    tmdbCastCreditId <- v A..: "credit_id"
    tmdbCastGender <- v A..:? "gender"
    tmdbCastPersonId <- v A..: "id"
    tmdbCastName <- v A..: "name"
    tmdbCastOrder <- v A..: "order"
    tmdbCastProfilePath <- v A..:? "profile_path"
    return TMDBCastMember {..}

instance FromJSON TMDBCrewMember where
  parseJSON = A.withObject "TMDBCrewMember" $ \v -> do
    tmdbCrewCreditId <- v A..: "credit_id"
    tmdbCrewDepartment <- v A..: "department"
    tmdbCrewGender <- v A..:? "gender"
    tmdbCrewPersonId <- v A..: "id"
    tmdbCrewJob <- v A..: "job"
    tmdbCrewName <- v A..: "name"
    tmdbCrewProfilePath <- v A..:? "profile_path"
    return TMDBCrewMember {..}

instance FromJSON Genre where
  parseJSON = A.withObject "Genre" $ \v -> do
    genreId <- v A..: "id"
    genreName <- v A..: "name"
    return Genre {..}

instance FromJSON GenreResponse where
  parseJSON = A.withObject "GenreResponse" $ \v -> do
    genres <- v A..: "genres"
    return GenreResponse {..}

instance FromJSON TMDBResponse where
  parseJSON = A.withObject "TMDBResponse" $ \v -> do
    results <- v A..: "results"
    return TMDBResponse {..}

instance ToJSON MediaItem where
  toJSON MediaItem {..} =
    object
      [ "id" .= mediaId,
        "title" .= mediaTitle,
        "type_" .= mediaType,
        "imageUrl" .= mediaImageUrl,
        "year" .= mediaYear,
        "rating" .= mediaRating,
        "description" .= mediaDescription,
        "backdropUrl" .= mediaBackdropUrl,
        "genres" .= mediaGenres,
        "cast" .= mediaCast,
        "directors" .= mediaDirectors
      ]

instance ToJSON CastMember where
  toJSON CastMember {..} =
    object
      [ "id" .= castId,
        "name" .= castName,
        "character" .= castCharacter,
        "profileUrl" .= castProfileUrl,
        "order" .= castOrder
      ]

instance ToJSON CrewMember where
  toJSON CrewMember {..} =
    object
      [ "id" .= crewId,
        "name" .= crewName,
        "job" .= crewJob,
        "department" .= crewDepartment,
        "profileUrl" .= crewProfileUrl
      ]

instance ToJSON CategoryOutput where
  toJSON CategoryOutput {..} =
    object
      [ "id" .= outId,
        "name" .= outName,
        "items" .= outItems
      ]

instance ToJSON OutputData where
  toJSON OutputData {..} =
    object
      [ "categories" .= categories
      ]

-- Categories to fetch
tmdbCategories :: [Category]
tmdbCategories =
  [ Category
      { catId = "continue-watching",
        catName = "Continue Watching",
        catEndpoint = "/movie/popular",
        catParams = [("page", "1")],
        catLimit = 8
      },
    Category
      { catId = "recently-added",
        catName = "Recently Added",
        catEndpoint = "/movie/now_playing",
        catParams = [("page", "1")],
        catLimit = 8
      },
    Category
      { catId = "recommended",
        catName = "Recommended For You",
        catEndpoint = "/movie/top_rated",
        catParams = [("page", "1")],
        catLimit = 8
      },
    Category
      { catId = "movie-library",
        catName = "Movies",
        catEndpoint = "/discover/movie",
        catParams = [("sort_by", "popularity.desc"), ("page", "1")],
        catLimit = 12
      },
    Category
      { catId = "tv-library",
        catName = "TV Shows",
        catEndpoint = "/tv/popular",
        catParams = [("page", "1")],
        catLimit = 12
      }
  ]

-- Logging helpers
logInfo :: String -> IO ()
logInfo = putStrLn

logError :: String -> IO ()
logError = hPutStrLn stderr

-- Custom alternative for Maybe values
mbOr :: Maybe a -> Maybe a -> Maybe a
mbOr a b = case a of
  Just _  -> a
  Nothing -> b

-- Fetch data from TMDB API
fetchFromTMDB :: String -> String -> [(String, String)] -> IO (Either String BL.ByteString)
fetchFromTMDB apiKey endpoint params = do
  let allParams = ("api_key", apiKey) : params
      url = apiBaseUrl ++ endpoint
      request = setRequestQueryString (map (\(k, v) -> (BC.pack k, Just (BC.pack v))) allParams) $ parseRequest_ url

  -- Log the request (without API key for security)
  logInfo $ "Requesting data from: " ++ url ++ paramsToString (filter (\(k, _) -> k /= "api_key") params)

  -- Make the request and handle potential exceptions
  response <- try $ httpLBS request :: IO (Either SomeException (Response BL.ByteString))
  case response of
    Left err ->
      return $ Left $ "Network error fetching from TMDB: " ++ show err

    Right res ->
      -- Check status code
      if getResponseStatusCode res `div` 100 == 2
        then return $ Right $ getResponseBody res
        else do
          -- Try to get error message from response
          let body = getResponseBody res
              statusCode = getResponseStatusCode res
              errorMsg = case eitherDecode body of
                Right obj -> case obj of
                  A.Object o ->
                    case KeyMap.lookup "status_message" o of
                      Just (A.String msg) -> T.unpack msg
                      _ -> "Unknown error"
                  _ -> "Unknown error"
                _ -> "Unknown error"

          return $ Left $ "HTTP error " ++ show statusCode ++ ": " ++ errorMsg
  where
    paramsToString :: [(String, String)] -> String
    paramsToString [] = ""
    paramsToString ps = "?" ++ intercalate "&" [k ++ "=" ++ v | (k, v) <- ps]

-- Fetch all genres
fetchGenres :: String -> IO (Either String (HashMap.HashMap Int String))
fetchGenres apiKey = do
  logInfo "Fetching movie genres..."
  movieGenresResult <- fetchFromTMDB apiKey "/genre/movie/list" []

  logInfo "Fetching TV genres..."
  tvGenresResult <- fetchFromTMDB apiKey "/genre/tv/list" []

  case (movieGenresResult, tvGenresResult) of
    (Right movieGenresData, Right tvGenresData) -> do
      let movieGenresEither = eitherDecode movieGenresData :: Either String GenreResponse
          tvGenresEither = eitherDecode tvGenresData :: Either String GenreResponse

      case (movieGenresEither, tvGenresEither) of
        (Right movieGenres, Right tvGenres) -> do
          let allGenres = genres movieGenres ++ genres tvGenres
              genreMap = HashMap.fromList [(genreId g, genreName g) | g <- allGenres]

          logInfo $ "Found " ++ show (HashMap.size genreMap) ++ " unique genres"
          return $ Right genreMap

        (Left err1, _) ->
          return $ Left $ "Error decoding movie genres: " ++ err1

        (_, Left err2) ->
          return $ Left $ "Error decoding TV genres: " ++ err2

    (Left err, _) ->
      return $ Left $ "Error fetching movie genres: " ++ err

    (_, Left err) ->
      return $ Left $ "Error fetching TV genres: " ++ err

-- Fetch credits (cast and crew) for a movie or TV show
fetchCredits :: String -> Int -> String -> IO (Either String TMDBCredit)
fetchCredits apiKey itemId mediaType = do
  let endpoint = if mediaType == "Movie"
                    then "/movie/" ++ show itemId ++ "/credits"
                    else "/tv/" ++ show itemId ++ "/credits"

  logInfo $ "Fetching credits for " ++ mediaType ++ " ID " ++ show itemId ++ "..."

  result <- fetchFromTMDB apiKey endpoint []
  case result of
    Left err ->
      return $ Left $ "Error fetching credits: " ++ err

    Right responseData -> do
      let creditsEither = eitherDecode responseData :: Either String TMDBCredit
      case creditsEither of
        Left err ->
          return $ Left $ "Error parsing credits: " ++ err

        Right credits -> do
          logInfo $ "Successfully fetched " ++ show (length (tmdbCast credits)) ++ " cast members"
          return $ Right credits

-- Convert TMDB movie to our format
convertMovieToMediaItem :: String -> HashMap.HashMap Int String -> TMDBMovie -> IO MediaItem
convertMovieToMediaItem apiKey genreMap movie = do
  -- Get credits for this movie/show
  creditsResult <- fetchCredits apiKey (tmdbId movie) (if tmdbTitle movie /= Nothing then "Movie" else "TVShow")

  let
    -- Get title from either movie title or TV show name
    title = fromMaybe "Unknown Title" (tmdbTitle movie `mbOr` tmdbName movie)

    -- Determine media type based on which field is present
    mediaType = if tmdbTitle movie /= Nothing then "Movie" else "TVShow"

    -- Create complete image URL or empty string if no poster
    imageUrl = maybe "" (\path -> imageBaseUrl ++ path) (tmdbPosterPath movie)

    -- Create complete backdrop URL if available
    backdropUrl = fmap (\path -> imageBaseUrl ++ path) (tmdbBackdropPath movie)

    -- Extract year from release date or air date
    year = extractYear (tmdbReleaseDate movie `mbOr` tmdbFirstAirDate movie)

    -- Get rating or default to 0
    rating = fromMaybe 0.0 (tmdbVoteAverage movie)

    -- Get description or use default
    description = fromMaybe "No description available." (tmdbOverview movie)

    -- Map genre IDs to genre names
    genreNames = maybe [] (mapMaybe (\gid -> HashMap.lookup gid genreMap)) (tmdbGenreIds movie)

    -- Process cast members (default to empty list if we couldn't fetch credits)
    castMembers = case creditsResult of
      Right credits ->
        -- Take top 10 cast members
        let topCast = take 10 (tmdbCast credits)
        in map (\member ->
          CastMember
            { castId = show (tmdbCastPersonId member)
            , castName = tmdbCastName member
            , castCharacter = tmdbCastCharacter member
            , castProfileUrl = fmap (\path -> imageBaseUrl ++ path) (tmdbCastProfilePath member)
            , castOrder = tmdbCastOrder member
            }) topCast
      Left _ ->
        []

    -- Process directors (default to empty list if we couldn't fetch credits)
    directors = case creditsResult of
      Right credits ->
        -- Filter crew for directors
        let directorCrew = filter (\c -> tmdbCrewJob c == "Director") (tmdbCrew credits)
        in map (\member ->
          CrewMember
            { crewId = show (tmdbCrewPersonId member)
            , crewName = tmdbCrewName member
            , crewJob = tmdbCrewJob member
            , crewDepartment = tmdbCrewDepartment member
            , crewProfileUrl = fmap (\path -> imageBaseUrl ++ path) (tmdbCrewProfilePath member)
            }) directorCrew
      Left _ ->
        []

  return MediaItem
    { mediaId = show (tmdbId movie)
    , mediaTitle = title
    , mediaType = mediaType
    , mediaImageUrl = imageUrl
    , mediaYear = year
    , mediaRating = rating
    , mediaDescription = description
    , mediaBackdropUrl = backdropUrl
    , mediaGenres = genreNames
    , mediaCast = castMembers
    , mediaDirectors = directors
    }
  where
    -- Helper function to extract year from a date string
    extractYear :: Maybe String -> Int
    extractYear Nothing = 2000 -- Default year if no date
    extractYear (Just dateStr) =
      case parseTimeM True defaultTimeLocale "%Y-%m-%d" dateStr of
        Just day ->
          let (y, _, _) = toGregorian day
          in fromIntegral y
        Nothing ->
          -- If we can't parse the full date, try to extract just the year
          case take 4 dateStr of
            yearStr | all (`elem` ['0'..'9']) yearStr ->
              read yearStr
            _ ->
              2000 -- Default year if parsing fails

-- Process a category
processCategory :: String -> HashMap.HashMap Int String -> Category -> IO (Either String CategoryOutput)
processCategory apiKey genreMap category = do
  logInfo $ "Fetching " ++ catName category ++ " from " ++ catEndpoint category ++ "..."

  result <- fetchFromTMDB apiKey (catEndpoint category) (catParams category)
  case result of
    Left err ->
      return $ Left $ "Error fetching " ++ catName category ++ ": " ++ err

    Right responseData -> do
      let responseEither = eitherDecode responseData :: Either String TMDBResponse
      case responseEither of
        Left err ->
          return $ Left $ "Error parsing " ++ catName category ++ " response: " ++ err

        Right response -> do
          let items = take (catLimit category) (results response)

          -- Convert each movie, now with async credit fetching
          mediaItems <- mapM (convertMovieToMediaItem apiKey genreMap) items

          logInfo $ "Successfully fetched " ++ show (length mediaItems) ++ " items for " ++ catName category
          return $ Right $ CategoryOutput (catId category) (catName category) mediaItems

-- Helper to convert Either to Maybe (used for filtering)
eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Left _) = Nothing
eitherToMaybe (Right b) = Just b

-- Show usage information
showUsage :: IO ()
showUsage = do
  logInfo "Usage: tmdb-fetcher [OUTPUT_PATH]"
  logInfo ""
  logInfo "Fetches movie and TV show data from The Movie Database (TMDB) API"
  logInfo "and saves it as JSON."
  logInfo ""
  logInfo "Arguments:"
  logInfo "  OUTPUT_PATH  Path where the output JSON will be saved"
  logInfo "               (defaults to 'movies.json' in current directory)"
  logInfo ""
  logInfo "Environment variables:"
  logInfo "  TMDB_API_KEY  Your TMDB API key (required)"
  logInfo ""
  logInfo "Example:"
  logInfo "  export TMDB_API_KEY=your_api_key_here"
  logInfo "  tmdb-fetcher ./public/data/movies.json"

-- Main function
main :: IO ()
main = do
  -- Check for help request
  args <- getArgs
  when ("--help" `elem` args || "-h" `elem` args) $ do
    showUsage
    exitFailure

  -- Get command line arguments
  let outputPath = case args of
        (path:_) -> path
        [] -> "movies.json"

  -- Check for TMDB API key
  apiKey <- lookupEnv "TMDB_API_KEY"
  case apiKey of
    Nothing -> do
      logError "Error: TMDB_API_KEY environment variable is not set."
      logError "Please set it to your TMDB API key."
      logError "Example: export TMDB_API_KEY=your_api_key_here"
      logError ""
      showUsage
      exitFailure

    Just key -> do
      logInfo $ "TMDB Data Fetcher"
      logInfo $ "----------------"
      logInfo $ "Output will be saved to: " ++ outputPath

      -- Fetch all genre data
      genresResult <- fetchGenres key
      case genresResult of
        Left err -> do
          logError $ "Error fetching genres: " ++ err
          exitFailure

        Right genreMap -> do
          -- Process each category in parallel
          categoryResults <- mapM (processCategory key genreMap) tmdbCategories

          -- Filter out categories that failed
          let successfulCategories = catMaybes $ map eitherToMaybe categoryResults
              failedCategories = length categoryResults - length successfulCategories

          -- Report on failures if any
          when (failedCategories > 0) $
            logError $ "Warning: " ++ show failedCategories ++ " categories failed to fetch."

          -- Proceed only if we have some successful data
          if null successfulCategories then
            do
              logError "Error: No categories were successfully fetched."
              exitFailure
          else
            do
              -- Create the final output data structure
              let outputData = OutputData successfulCategories
                  jsonOutput = encode outputData

              -- Create output directory if needed
              createDirectoryIfMissing True (takeDirectory outputPath)

              -- Write the data to file
              BL.writeFile outputPath jsonOutput
              logInfo $ "Successfully wrote data for " ++ show (length successfulCategories)
                     ++ " categories to " ++ outputPath
              logInfo $ "Total size: " ++ show (BL.length jsonOutput `div` 1024) ++ " KB"
