import os

from faker_db import FakerDb

db = FakerDb(os.environ["DATABASE_URL"])
db.install()
print("ok:", db.users("pl_PL", 42, 0, 1)[0]["Name"])
