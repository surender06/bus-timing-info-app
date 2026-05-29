# Bus Timing Info App

A local bus timing web app with passenger, driver, admin, and backend API features.

## Features

- Search bus routes by number, stop, or destination
- View next bus timing, stops, fare, and travel duration
- Driver can update current stop, delay, and trip status
- Passenger screen refreshes backend updates automatically
- Passengers can submit feedback with rating and experience details
- Admin can add and delete bus routes
- Driver and admin areas are password protected
- Route and driver data is saved in `data.json`

## Run Locally

Install Node.js, then run:

```bash
npm start
```

Open:

```text
http://localhost:4173
```

On Windows, you can also double-click:

```text
Start Bus App.bat
```

## Deploy On Render

1. Push this project to GitHub.
2. Create a new Render web service from the repo.
3. Use `npm install` as the build command.
4. Use `npm start` as the start command.
5. Add environment variables for safer passwords:
   - `DRIVER_KEY`
   - `ADMIN_KEY`

The app uses `process.env.PORT`, so Render can run it on the correct hosted port.

## Default Demo Passwords

- Driver: `driver123`
- Admin: `admin123`

For public deployment, change these using Render environment variables.

## Note

This version stores data in `data.json`, which is fine for a prototype or demo. For real public use, replace it with a database like PostgreSQL or MongoDB.
