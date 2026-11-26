# Production deployment

Pathfinder is deployed on Firebase Hosting at [pathfinder-4de02.web.app](https://pathfinder-4de02.web.app). The Hosting site, production App Check registration, and reCAPTCHA Enterprise provider are configured for this Firebase project.

## One-time Firebase setup

1. The default Hosting site `pathfinder-4de02` is already created.
2. The production reCAPTCHA Enterprise score key is registered in Firebase App Check for `pathfinder-4de02.web.app` and `pathfinder-4de02.firebaseapp.com`.
3. Confirm both domains remain authorized in Firebase Authentication when enabling sign-in providers.
4. For a new build environment, supply the Firebase web app configuration and production App Check **site key** locally. Never place a reCAPTCHA secret or service-account private key in the Flutter app.
5. Log in to the Firebase CLI with an account that has Hosting deploy access: `firebase login`.

Registering the app in App Check and enabling enforcement makes Firebase reject requests without valid App Check tokens. Keep the local debug token for preview only; production builds use the reCAPTCHA Enterprise provider.

## Build and deploy from this computer

Install the Firebase CLI if needed, then run:

```sh
export FIREBASE_APPCHECK_SITE_KEY="your-production-recaptcha-enterprise-site-key"
PATHFINDER_FLUTTER_BIN="/path/to/flutter/bin/flutter" \
PATHFINDER_FIREBASE_BIN="/path/to/firebase" \
  ./scripts/deploy_firebase_hosting.sh
```

The script builds the Flutter app in release mode and deploys only Hosting to `pathfinder-4de02`. It refuses to deploy without the production site key. `firebase.web.json` remains local and gitignored; it contains the Firebase Web SDK configuration used by Flutter.

## GitHub and Cloud Build deployments

The GitHub Actions Cloud Run workflow reads `GCP_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_AUTH_DOMAIN`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_APP_ID`, and `FIREBASE_APPCHECK_SITE_KEY` from repository secrets and passes the Firebase values into the Flutter build. Cloud Build uses the matching `_FIREBASE_*` substitutions, including `_FIREBASE_APPCHECK_SITE_KEY`. These are public Firebase Web app values embedded in the web bundle. Firebase Auth providers and authorized domains still need to be enabled in the Firebase console. Missing GitHub secrets are reported by name before Google authentication begins.

The image workflows publish to Artifact Registry at `us-central1-docker.pkg.dev/PROJECT_ID/pathfinder/pathfinder`. Enable `artifactregistry.googleapis.com`, `cloudbuild.googleapis.com`, and `run.googleapis.com`, then create the `pathfinder` Docker repository in `us-central1`. The GitHub deploy identity needs Artifact Registry Writer, Cloud Run Admin, and Service Account User on the runtime service account. For Workload Identity Federation, restrict the provider to this repository and the `main` branch, then grant the federated identity permission to use the deploy service account. Configure GitHub with `GCP_WORKLOAD_IDENTITY_PROVIDER` and `GCP_SERVICE_ACCOUNT` (recommended); the workflow also supports `GCP_SA_KEY` as a fallback. Configure the Cloud Build service account with Artifact Registry Writer and Cloud Run deploy permissions. Do not upload `.env.local`, `firebase.web.json`, reCAPTCHA secret keys, App Check debug tokens, or service-account private keys to the repository.

## Content readiness

Review and publish career roadmaps and quiz versions before relying on Firestore for production content. Firestore rules intentionally expose only published versions; draft seed data is still read from the local bundled JSON files.
