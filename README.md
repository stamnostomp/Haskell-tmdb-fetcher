# TMDB Data Fetcher

A standalone Haskell application that fetches movie and TV show data from The Movie Database (TMDB) API and saves it as standard JSON, ready to be consumed by applications in any programming language or framework.

## Features

- Fetches real movie and TV show data from TMDB
- Organizes content into customizable categories
- Includes posters, ratings, descriptions, and genres
- Outputs a clean, structured JSON file
- Can be integrated with any application that can read JSON

## Requirements

- GHC (Glasgow Haskell Compiler)
- Cabal
- TMDB API key (get one from [themoviedb.org](https://www.themoviedb.org/settings/api))

## Quick Start with Nix

The easiest way to build and run the fetcher is with Nix Flakes:

```bash
# Set your TMDB API key
export TMDB_API_KEY=your_api_key_here

# Run with default output path (./output/movies.json)
nix run

# Or specify a custom output path
nix run . -- path/to/output/movies.json
```

## Manual Setup

If you prefer not to use Nix:

```bash
# Update Cabal package database
cabal update

# Build the project
cabal build

# Run the fetcher (outputs to movies.json in current directory)
export TMDB_API_KEY=your_api_key_here
cabal run

# Or specify a custom output path
cabal run -- path/to/output/movies.json
```

## Development

For development work:

```bash
# Enter the Nix development shell
nix develop

# Then you can use:
build               # Build the project
run                 # Run with default output path
run-with-path PATH  # Run with custom output path
```

## Customizing Data

To fetch different data:

1. Edit the `tmdbCategories` list in `Main.hs`
2. Each category definition includes:
   - `catId`: Unique identifier
   - `catName`: Display name
   - `catEndpoint`: TMDB API endpoint
   - `catParams`: Query parameters
   - `catLimit`: Maximum items to include

Example of a custom category:

```haskell
Category
  { catId = "oscar-winners",
    catName = "Oscar-Winning Films",
    catEndpoint = "/discover/movie",
    catParams = [
      ("with_genres", "18"),
      ("sort_by", "vote_average.desc"),
      ("vote_count.gte", "1000"),
      ("page", "1")
    ],
    catLimit = 10
  }
```

## Output Format

The generated JSON has this structure:

```json
{
  "categories": [
    {
      "id": "continue-watching",
      "name": "Continue Watching",
      "items": [
        {
          "id": "123",
          "title": "Movie Title",
          "type_": "Movie",
          "imageUrl": "https://image.tmdb.org/...",
          "year": 2023,
          "rating": 8.5,
          "description": "Movie description...",
          "backdropUrl": "https://image.tmdb.org/...",
          "genres": ["Action", "Sci-Fi"]
        },
        // More items...
      ]
    },
    // More categories...
  ]
}
```

## Integration with Various Frameworks

Since the output is standard JSON, you can use this data with virtually any programming language or framework:

### JavaScript/TypeScript

```javascript
// Fetch the JSON file
fetch('/data/movies.json')
  .then(response => response.json())
  .then(data => {
    // Process the data
    const categories = data.categories;
    // Render UI with the movie data
  });
```

### Python

```python
import json

# Load the JSON file
with open('path/to/movies.json', 'r') as file:
    data = json.load(file)
    
# Access the data
categories = data['categories']
for category in categories:
    print(f"Category: {category['name']}")
    for item in category['items']:
        print(f"  - {item['title']} ({item['year']})")
```

### React

```jsx
import { useEffect, useState } from 'react';

function MovieList() {
  const [categories, setCategories] = useState([]);
  
  useEffect(() => {
    fetch('/data/movies.json')
      .then(res => res.json())
      .then(data => setCategories(data.categories))
      .catch(error => console.error('Error loading movie data:', error));
  }, []);
  
  return (
    <div>
      {categories.map(category => (
        <div key={category.id}>
          <h2>{category.name}</h2>
          <div className="movie-grid">
            {category.items.map(movie => (
              <div key={movie.id} className="movie-card">
                <img src={movie.imageUrl} alt={movie.title} />
                <h3>{movie.title}</h3>
                <div>{movie.year} ★ {movie.rating}</div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
```

### Swift

```swift
struct Category: Decodable {
    let id: String
    let name: String
    let items: [MediaItem]
}

struct MediaItem: Decodable {
    let id: String
    let title: String
    let type_: String
    let imageUrl: String
    let year: Int
    let rating: Float
    let description: String
    let backdropUrl: String?
    let genres: [String]
}

struct TMDBData: Decodable {
    let categories: [Category]
}

// Load and parse the JSON
if let url = Bundle.main.url(forResource: "movies", withExtension: "json") {
    do {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let tmdbData = try decoder.decode(TMDBData.self, from: data)
        
        // Use the data
        for category in tmdbData.categories {
            print("Category: \(category.name)")
        }
    } catch {
        print("Error parsing JSON: \(error)")
    }
}
```

## Automation

For production use, you might want to keep the movie data fresh. Here's how you can automate updates:

### Using cron

```bash
# Edit your crontab
crontab -e

# Add a line to update movies.json daily at 3am
0 3 * * * export TMDB_API_KEY=your_api_key_here && cd /path/to/tmdb-fetcher && cabal run -- /path/to/output/movies.json
```

### Using GitHub Actions

Create a workflow file that runs on a schedule:

```yaml
name: Update Movie Data

on:
  schedule:
    - cron: '0 0 * * 0'  # Run every Sunday at midnight
  workflow_dispatch:     # Allow manual runs

jobs:
  update-data:
    runs-on: ubuntu-latest
    steps:
      # Setup steps...
      
      - name: Fetch movie data
        env:
          TMDB_API_KEY: ${{ secrets.TMDB_API_KEY }}
        run: |
          cd tmdb-fetcher
          nix run . -- ../public/data/movies.json
```

## Why Haskell?

This project uses Haskell for several benefits:

1. **Type Safety**: Prevents many common bugs at compile time
2. **Pure Functions**: Makes code more predictable and testable
3. **Elegant JSON Handling**: With the Aeson library
4. **Expressive Error Handling**: Using the Either monad

## License

This project is licensed under the MIT License - see the LICENSE file for details.
