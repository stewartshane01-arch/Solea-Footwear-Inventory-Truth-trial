# Running Instructions for Solea Footwear Inventory Truth

## Prerequisites
- Python 3.9+
- Docker and Docker Compose (optional, for containerized deployment)
- PostgreSQL database (local, hosted, or via Docker)
- eBay Developer account and API credentials
- Google account with Gmail API access

## Setup Steps

### 1. Clone the Repository
```bash
cd /Users/abdullahalsaimun/Desktop/devxhub/Solea-Footwear-Inventory-Truth
```

### 2. Create Virtual Environment (optional but recommended)
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Set Up Database
Choose one of the following approaches:

#### Option A: Using Docker (Recommended)
```bash
# Start PostgreSQL container
docker-compose up -d

# Connect to PostgreSQL at localhost:5432 with credentials from .env
```

If your container is already running and you need to apply or re-apply the schema manually:
```bash
# Apply schema.sql to the running postgres container
docker compose exec -T postgres psql -U "${DB_USER:-postgres}" -d "${DB_NAME:-inventory_db}" -f /docker-entrypoint-initdb.d/init.sql
```

Notes:
- The file `schema.sql` is mounted as `/docker-entrypoint-initdb.d/init.sql` in the container.
- Files in `/docker-entrypoint-initdb.d/` run automatically only when Postgres initializes a brand-new data volume.
- If you want automatic init to run again from scratch, remove the volume and start again:

```bash
docker compose down -v
docker compose up -d
```

#### Option B: Local PostgreSQL
Execute the schema in `schema.sql` in your PostgreSQL database:
```sql
-- Connect to your PostgreSQL database and run:
\i schema.sql
```

### 5. Configure Environment Variables
Copy and update the `.env` file with your specific credentials:
- Database connection details
- eBay API credentials
- Gmail API credentials

### 6. eBay API Setup
1. Register for eBay Developer Program at https://developer.ebay.com/
2. Create an application in eBay Developer Portal
3. Add your credentials to the `.env` file:
   - EBAY_APP_ID
   - EBAY_CERT_ID
   - EBAY_DEV_ID

### 7. Gmail API Setup
1. Enable Gmail API in Google Cloud Console
2. Create OAuth 2.0 credentials
3. Download credentials JSON file
4. Place it in the project root or path specified in GMAIL_CREDENTIALS_PATH
5. The first run will prompt for authentication to create token.json

### 8. Run the Application

#### Option A: Direct Python Execution (requires local or Docker PostgreSQL)
```bash
python app.py
```

The application will start on port 9500 by default.

## Key Endpoints
- Health check: `GET /health`
- Dashboard: `GET /api/dashboard`
- Products: `GET /api/products`
- Units: `GET /api/units`
- Sync: `POST /api/sync/ebay`
- Returns (after implementation): `GET /api/returns`

## Services
- Automatic eBay sync (if enabled)
- Delisting service for sold items
- Cross-listing to other platforms
- Email processing for sales notifications
- Audit services for data integrity

## Docker Services
- PostgreSQL database (port 5432) - for the main database

## Troubleshooting
- Make sure all environment variables are properly set
- Verify database connectivity
- Ensure eBay API credentials are valid and permissions are set
- Check that Gmail API is properly authorized
- For Docker issues, ensure Docker Desktop is running
- If you get psycopg2 compilation errors, install PostgreSQL development libraries:
  - Ubuntu/Debian: `sudo apt-get install libpq-dev python3-dev`
  - macOS: `brew install postgresql`
  - Windows: Use psycopg2-binary package (already in requirements.txt)