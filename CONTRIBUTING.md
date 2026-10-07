# Contributing

Build and verify using `scripts/test.sh`, `scripts/build-app.sh`, and
`scripts/build-cli.sh`. See `docs/ARCHITECTURE.md` for the shared core.

Documentation lives in `website/content/`. Update relevant Markdown pages and
`CHANGELOG.md` with feature changes. The Nuxt site is rebuilt from these pages
on every push to main. See the [contributing guide](https://kkz6.github.io/Morrow/docs/contributing).

Use Node 24.15 or newer for the website:

```sh
cd website
npm ci
npm run generate
npm run check
```

Keep all user data and credentials outside the repository. Use an isolated
`MORROW_HOME` for native integration checks and stop its managed jobs before
removing test files.
