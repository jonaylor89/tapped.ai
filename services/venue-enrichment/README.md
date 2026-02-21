# Venue Enrichment Tool

A modern, AI-powered Rust application that enriches music venue data by intelligently scraping the web using the Exa Search API and LLM reasoning.

## Features

- **AI-Powered Discovery**: Uses Exa Search API to find relevant venue information across the web
- **Intelligent Source Ranking**: LLM evaluates and ranks sources by quality and relevance  
- **Agentic Scraping**: AI generates custom extraction strategies for each source
- **Concurrent Processing**: Processes multiple venues simultaneously with rate limiting
- **Schema Validation**: Ensures all output conforms to the defined JSON schema
- **Flexible Input**: Supports both CSV and JSON input formats
- **Comprehensive Extraction**: Extracts contact info, social media links, descriptions, and more

## Quick Start

1. **Clone and build**:
   ```bash
   git clone <repository-url>
   cd venue-enrichment
   cargo build --release
   ```

2. **Set up API keys**:
   ```bash
   cp .env.example .env
   # Edit .env with your actual API keys
   ```

3. **Run with sample data**:
   ```bash
   cargo run -- --input examples/small_test.csv --dry-run --verbose
   ```

4. **Run with real API calls**:
   ```bash
   cargo run -- --input examples/venues.csv
   ```

## Installation

### Prerequisites

- Rust 1.70+ (with 2024 edition support)
- Exa API key (get one at [exa.ai](https://exa.ai))
- OpenAI API key or compatible LLM API

### Build from Source

```bash
git clone <repository-url>
cd venue-enrichment
cargo build --release
```

## Configuration

### API Keys

#### Option 1: Using .env file (Recommended)

Create a `.env` file in the project root:

```bash
cp .env.example .env
# Edit .env with your actual API keys
```

Example `.env` file:
```bash
EXA_API_KEY=your-exa-api-key-here
OPENAI_API_KEY=your-openai-api-key-here
```

#### Option 2: Environment variables

Set your API keys as environment variables:

```bash
export EXA_API_KEY="your-exa-api-key-here"
export OPENAI_API_KEY="your-openai-api-key-here"
```

#### Option 3: Command-line arguments

```bash
./target/release/venue-enrichment \
  --exa-api-key "your-exa-key" \
  --llm-api-key "your-openai-key" \
  --input venues.csv
```

### Configuration File

Copy and customize the configuration file:

```bash
cp config.toml config.local.toml
# Edit config.local.toml with your preferences
```

The configuration file controls:
- **Blocklist**: Domains to exclude from scraping
- **Scraping**: Rate limits, timeouts, user agents
- **Concurrency**: Parallel processing limits
- **Proxy**: Optional proxy configuration

### Proxy Setup (Optional)

If you need to use a proxy, uncomment and configure the proxy section in `config.toml`:

```toml
[proxy]
http_proxy = "http://proxy.example.com:8080"
https_proxy = "https://proxy.example.com:8080"
```

## Usage

### Input Formats

#### CSV Format

Create a CSV file with venues:

```csv
name,context
The Anthem,Washington DC
Madison Square Garden,New York City
Red Rocks Amphitheatre,Colorado
The Fillmore,San Francisco
```

#### JSON Format

Or use JSON format:

```json
[
  {
    "name": "The Anthem",
    "context": "Washington DC"
  },
  {
    "name": "Madison Square Garden", 
    "context": "New York City"
  }
]
```

### Running the Tool

Basic usage (with .env file):

```bash
cargo run -- --input venues.csv
```

Or with explicit API keys:

```bash
cargo run -- --input venues.csv --exa-api-key YOUR_EXA_KEY --llm-api-key YOUR_OPENAI_KEY
```

With all options:

```bash
cargo run -- \
  --input venues.csv \
  --output enriched_venues.json \
  --config config.toml \
  --exa-api-key YOUR_EXA_KEY \
  --llm-api-key YOUR_OPENAI_KEY \
  --llm-model gpt-4 \
  --max-concurrent 5 \
  --verbose
```

### Command Line Options

```
USAGE:
    venue-enrichment [OPTIONS] --input <INPUT> --exa-api-key <EXA_API_KEY>

OPTIONS:
    -i, --input <INPUT>                    Input file path (CSV or JSON)
    -o, --output <OUTPUT>                  Output file path [default: output/venues.json]
    -c, --config <CONFIG>                  Configuration file path [default: config.toml]
        --max-concurrent <MAX_CONCURRENT>  Maximum concurrent venues [default: 3]
        --exa-api-key <EXA_API_KEY>        Exa API key [env: EXA_API_KEY]
        --llm-api-key <LLM_API_KEY>        LLM API key [env: LLM_API_KEY]
        --llm-base-url <LLM_BASE_URL>      LLM API base URL [default: https://api.openai.com/v1]
        --llm-model <LLM_MODEL>            LLM model [default: gpt-3.5-turbo]
        --dry-run                          Dry run mode (no API calls)
    -v, --verbose                          Verbose logging
    -h, --help                             Print help
```

## Output

The tool generates a JSON file containing enriched venue data:

```json
[
  {
    "name": "The Anthem",
    "description": "A premier music venue in Washington DC...",
    "email": "info@theanthem.com",
    "phone": "(202) 888-0020",
    "website": "https://www.theanthem.com",
    "facebookUrl": "https://www.facebook.com/theanthemdC",
    "twitterUrl": "https://twitter.com/theanthemdC",
    "instagramUrl": "https://www.instagram.com/theanthemdC",
    "logoUrl": "https://www.theanthem.com/logo.png",
    "idealPerformerProfile": "Mid-sized to large acts, rock, pop, hip-hop",
    "provenance": {
      "email": "https://www.theanthem.com/contact",
      "phone": "https://www.theanthem.com/contact",
      "description": "https://www.theanthem.com"
    }
  }
]
```

### Provenance Tracking

Each extracted field includes provenance metadata showing which source it came from, enabling transparency and validation of the enrichment process.

## Architecture

### Core Components

1. **Agent** (`src/agent.rs`): Handles LLM reasoning and Exa API integration
2. **WebScraper** (`src/utils.rs`): Manages concurrent web scraping with rate limiting
3. **DataExtractor** (`src/utils.rs`): Extracts structured data from HTML using regex and CSS selectors
4. **Models** (`src/models.rs`): Defines data structures and JSON schema validation

### Processing Pipeline

1. **Discovery**: Query Exa Search API for venue-related URLs
2. **Ranking**: AI evaluates source quality and relevance
3. **Selection**: Choose optimal sources based on missing fields
4. **Scraping**: Fetch content with respect for rate limits and robots.txt
5. **Extraction**: Use heuristics and AI to extract structured data
6. **Validation**: Ensure data quality and schema compliance
7. **Output**: Generate enriched venue JSON with provenance

### AI Integration

The tool uses AI at multiple stages:

- **Source Ranking**: Evaluate which search results are most likely to contain venue info
- **Source Selection**: Choose optimal sources to scrape based on missing fields
- **Extraction Strategy**: Generate custom scraping instructions for each source
- **Data Extraction**: Parse unstructured HTML into structured JSON when heuristics fail

## Development

### Running Tests

```bash
cargo test
```

### Code Structure

```
src/
├── main.rs           # CLI and orchestration
├── models.rs         # Data structures and schema
├── agent.rs          # AI reasoning and API integration  
├── utils.rs          # Web scraping and data extraction
└── lib.rs            # Library exports (optional)

config.toml           # Configuration
.env.example          # Example environment variables file
.gitignore            # Git ignore file (excludes .env files)
examples/             # Example input files
output/              # Generated output files
```

### Adding New Extraction Methods

To add new data extraction methods:

1. Add the method to `DataExtractor` in `utils.rs`
2. Update `extract_with_instructions()` to handle the new method
3. Modify AI prompts in `agent.rs` to suggest the new method when appropriate

### Custom LLM Providers

The tool supports any OpenAI-compatible API. To use a different provider:

```bash
cargo run -- \
  --llm-base-url "https://api.anthropic.com/v1" \
  --llm-model "claude-3-sonnet" \
  --input venues.csv
```

## Troubleshooting

### Common Issues

**Exa API Errors**
- Verify your Exa API key is correct and has sufficient quota
- Check that you're using the latest API format (the tool has been updated for the current Exa API)
- Use `--verbose` flag to see detailed API error messages
- Ensure your API key has access to the neural search feature

**Rate Limiting**
- Adjust `requests_per_second` in config.toml
- Increase `delay_between_requests_ms` for aggressive rate limiting
- Use `--max-concurrent 1` to process venues sequentially

**LLM API Errors**
- Verify your OpenAI API key is correct and has sufficient quota
- Check network connectivity and proxy settings
- Use `--verbose` flag for detailed error logging
- Try a different model if the current one is unavailable

**Empty Results** 
- Verify venue names are spelled correctly
- Add more context (city, state) to improve search results
- Check if sources are being blocked by the blocklist

**Memory Usage**
- Large HTML pages can use significant memory
- Consider reducing `max_pages_per_site` in config
- Process fewer venues concurrently with `--max-concurrent`

### Debug Mode

Run with verbose logging to see detailed processing information:

```bash
RUST_LOG=debug cargo run -- --verbose --input venues.csv
```

## License

[Specify your license here]

## Contributing

[Add contribution guidelines here]

## Changelog

### v0.1.1
- Updated Exa Search API integration to match latest API specification
- Added dotenv support for easier API key management
- Switched from anyhow to color-eyre for beautiful error reporting with stack traces
- Enhanced error handling and logging with detailed API-specific messages
- Added helpful tips for common authentication issues (401 errors show key hints)
- Improved debug logging with request/response details
- Updated README with better troubleshooting guide

### v0.1.0
- Initial release with basic venue enrichment functionality
- Exa Search API integration
- OpenAI LLM integration  
- Multi-source web scraping
- JSON schema validation
- Concurrent processing with rate limiting