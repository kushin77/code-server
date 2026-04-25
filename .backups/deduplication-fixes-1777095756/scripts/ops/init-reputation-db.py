import sys
import os
sys.path.append(os.path.join(os.getcwd(), 'apps', 'reputation-engine'))
from models import Base
from sqlalchemy import create_engine

def init_local_db():
    database_url = 'sqlite:///reputation_engine.db'
    engine = create_engine(database_url)
    Base.metadata.create_all(bind=engine)
    print(f"SQLite database created successfully at {os.path.abspath('reputation_engine.db')}")

if __name__ == "__main__":
    init_local_db()
