## Create your admin account

Open a terminal for this app from the Cloudron dashboard and run:

```
source /app/code/venv/bin/activate
funkwhale-manage fw users create --superuser --username yourname --email you@example.com --password yourpassword
```

Note: Funkwhale does not allow "admin" as a username. Change your password after first login.

## Music library

Upload music through the web interface or place files directly in `/app/data/music/`.

## Data migration

If you are migrating from an existing Funkwhale instance, see the [Cloudron documentation](https://docs.cloudron.io) for database restore instructions. You will need to:

1. Import your PostgreSQL database dump
2. Copy your media and music files to `/app/data/media/` and `/app/data/music/`
3. Restart the app
