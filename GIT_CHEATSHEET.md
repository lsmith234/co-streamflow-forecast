# Git cheat sheet (the only 4 things you need)

The repo lives in two places: **GitHub** (the master copy, which the nightly job also writes to) and **your laptop** (where you edit). Git keeps them in sync.

## First time only: get the repo onto your laptop

**RStudio:** File → New Project → Version Control → Git → paste
`https://github.com/lsmith234/co-streamflow-forecast.git` → pick a folder → Create.

(Or use **GitHub Desktop**: File → Clone repository → pick it from the list.)

## Every work session

| Step | When | RStudio (Git tab, top-right pane) | GitHub Desktop |
|---|---|---|---|
| **1. Pull** | **Always first.** The nightly job adds files every day | blue ⬇ **Pull** | **Fetch origin** → **Pull** |
| **2. Edit** | do your work | — | — |
| **3. Commit** | saves a snapshot with a note | tick the files → **Commit** → write a message → Commit | tick files → write summary → **Commit to main** |
| **4. Push** | sends your commits to GitHub | green ⬆ **Push** | **Push origin** |

**Rule of thumb:** Pull → work → Commit → Pull → Push.

## If something goes wrong

- **"Push rejected / updates were rejected"**: the nightly job pushed while you were working. **Pull**, then **Push** again.
- **Merge conflict in a `data/` file**: you edited data the bot also changed. Easiest fix: keep GitHub's version. In the terminal:
  `git checkout --theirs data/ && git add data/ && git commit -m "keep bot data"`, then push.
  Generally, **don't hand-edit anything in `data/`**. Let the scripts write it.
- **Stuck / confused**: don't delete anything. Ask Claude, and paste the error message.

## Good habits

- Commit small and often, with messages like "add SNOTEL ingest" or "tune gore 1wk model".
- Never commit passwords or API keys. Put them in `.Renviron`, which git ignores.
