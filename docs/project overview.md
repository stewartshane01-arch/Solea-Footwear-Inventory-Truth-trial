1

2

3

What our current software does
We run an e-commerce resale business focused on pre-owned shoes. Our internal software is
being built to act as the source of truth for inventory, listings, and marketplace status.
Right now, the software is centered around Supabase (PostgreSQL) and is intended to support
our listing and crosslisting workflow across marketplaces.
At a high level, the software currently does or is intended to do the following:
● Store our inventory records in Supabase
● Track each pair of shoes by SKU / barcode
● Connect product records to listing records
● Track marketplace listing IDs and statuses
● Support crosslisting from our main marketplace to other marketplaces
● Help manage delisting when an item sells
● Maintain data needed for relisting and inventory control
● Serve as the backend foundation for future AI tools for condition grading, listing
assistance, and pricing
How our business workflow works
Our workflow is generally:
1. We receive inventory
2. Each pair is photographed
3. Each pair is assigned a barcode / SKU
4. A listing is created for that pair
5. The pair may then be crosslisted to additional marketplaces
6. When an item sells on one marketplace, the corresponding listings on other
marketplaces need to be ended or updated
7. The software is meant to track these records and relationships centrally in Supabase
Each pair is usually treated as a unique unit, even if multiple pairs are similar.
How the current software is structured
The software is built around Supabase as the backend and source of truth.
It appears to include or be intended to include tables and logic for things like:
● Products / inventory records
● Units or SKU-level records
● Listings
● Marketplace-specific identifiers
● Statuses for active, sold, ended, or relisted items
● Cross-platform mapping between one internal item and multiple marketplace
listings
The goal is for Supabase to hold the core operational data instead of relying on spreadsheets or
third-party platforms as the true source of record.
How listing and crosslisting work in the system
Our main listing source is eBay.
The software is meant to support a flow where:
● an item is listed on eBay
● that item is represented in Supabase
● the item can then be crosslisted to other marketplaces
● Supabase stores the mapping between the internal SKU and each marketplace listing ID
● when a sale occurs on one platform, the software should help trigger updates or delisting
on the others
This mapping layer is very important to us because we need to avoid duplicate sales and
inventory mismatches.
Email tracking / marketplace signal handling
Part of the broader workflow also involves tracking marketplace events that may come in
through email, such as marketplace sale notifications.
The software may need to:
● parse or track those sale signals
● match them to the correct SKU or listing
● update Supabase
● trigger delisting or inventory updates accordingly
This is part of the operational flow we want the developer to understand and help improve.
What we need help with right now
Our immediate goal is not to build new features from scratch.
Right now we need help with:
● understanding the current backend structure
● confirming how the current system works
● identifying where the logic or data model is broken
● validating table relationships and workflows
● cleaning up issues in the current Supabase setup
● making sure the software is stable and correct before we expand it further
In other words, we need someone who can first audit, understand, and improve the current
system before helping build the next phase.
What we plan to build on top of this
Once the current system is cleaned up and stable, we plan to build additional tools on top of it,
including:
● AI-assisted condition grading from photos
● AI-assisted listing help
● pricing recommendations based on historical data and condition
● stronger automation around crosslisting and delisting
So the current backend is intended to become the foundation for a much larger operational
system.