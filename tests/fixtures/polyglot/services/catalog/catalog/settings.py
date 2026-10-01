import os

SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
DATABASES = {"default": {"ENGINE": "django.db.backends.postgresql", "NAME": os.environ.get("CATALOG_DB")}}
