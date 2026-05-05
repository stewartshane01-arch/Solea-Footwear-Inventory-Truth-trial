from dotenv import load_dotenv
load_dotenv()

from database import SessionLocal
from sync_service import SyncService

db = SessionLocal()

try:
    service = SyncService(db)
    result = service.sync_ebay_listings()
    print(result)
finally:
    db.close()
