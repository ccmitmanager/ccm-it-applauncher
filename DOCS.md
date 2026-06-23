# CCM IT App Launcher — Documentation

A static site generator that produces a per–business-unit grid of app shortcuts. Content and structure lives in three JSON files under `_data/`; a build script turns them into one static HTML page per unit.

---

## Data files (`_data/`)

### `units.json`

An array of business units. Each unit becomes its own page at `/<code>/`.

| Field            | Type   | Purpose                                                             |
| ---------------- | ------ | ------------------------------------------------------------------- |
| `code`           | string | Unique short code. **Also the output folder name** (e.g. `BCCC`).   |
| `name`           | string | Full display name (page title, logo alt text).                      |
| `shortName`      | string | Short label shown in the top navigation bar.                        |
| `accent`         | string | Hex accent colour for the page (e.g. `#313855`).                    |
| `logo`           | string | Root-relative path to the unit logo (e.g. `/style/ccm-logo.png`).   |
| `collegeAppsUrl` | string | URL for the "College Apps" link in the nav bar.                     |
| `tags`           | array  | Tags used for **section** visibility (e.g. `["school"]`).           |

For example:

```jsonc
  {
    "code": "CCMIT",
    "name": "CCM IT Services",
    "shortName": "CCM IT",
    "accent": "#22325d",
    "logo": "/style/ccm-logo.png",
    "collegeAppsUrl": "https://ccmschools.app/go/",
    "tags": ["ccm-internal"]
  }
```

Initial tags are `school` and `ccm-internal` but arbitrarily more could be added.

### `sections.json`

An array of sections — the filter tabs shown on each page.

| Field     | Type   | Purpose                                                                    |
| --------- | ------ | -------------------------------------------------------------------------- |
| `id`      | string | Unique id. **Must match a key in `shortcuts.json`** and is used as grid id. |
| `label`   | string | Text on the filter/tab button.                                             |
| `only`    | string \| array | *(optional)* Show only for units whose `code` or `tags` match.    |
| `exclude` | string \| array | *(optional)* Hide for units whose `code` or `tags` match.         |

A section only appears on a unit's page if it is visible for that unit **and** has at least one visible shortcut.

Example:

```jsonc
  {
    "id": "support",
    "label": "Technical Support",
    "only": "school"
  },
  {
    "id": "ms-portals",
    "label": "Microsoft Portals",
    "only": "ccm-internal"
  }
```

### `shortcuts.json`

A top-level **object keyed by section `id`**. Each value is an array of shortcut entries.

```jsonc
{
  "ms-portals": [
    { "id": "intune", "href": "https://in.cmd.ms", "icon_src": "svg/microsoftIntune.svg", "label": "Intune" }
  ],
  "ccm-t2-services": [
    { "id": "mfa", "href": "https://mysignins.microsoft.com/security-info", "icon": "MFA", "label": "Manage MFA", "only": ["CCMIT"] }
  ]
}
```

| Field      | Type   | Purpose                                                                            |
| ---------- | ------ | ---------------------------------------------------------------------------------- |
| `id`       | string | Identifier for the shortcut (unique within its section).                           |
| `href`     | string | Link target.                                                                       |
| `label`    | string | Text shown under the icon.                                                          |
| `icon`     | string | **Text icon** — renders a coloured square containing this short text.              |
| `icon_src` | string | **Image icon** — path under `icons/` (e.g. `svg/teams.svg`, `webp/edval.webp`).    |
| `bg`       | string | *(optional)* Background colour behind an image icon (hex or CSS colour name).      |
| `only`     | array  | *(optional)* Show only for these unit **codes**, e.g. `["BCCC"]`.                   |
| `exclude`  | array  | *(optional)* Show for all units **except** these codes.                            |

**Icon choice:** give a shortcut **either** `icon` (text tile) **or** `icon_src` (image) — not both.

**Visibility precedence:** if `only` is present it wins; otherwise `exclude` applies; otherwise the shortcut shows for every unit.

## Combining unit and section tags for shortcut visibility

In this structure an individual shortcut can only be a part of one section; so a link to Outlook Online would need to be created once for Students and again for Staff. Section tags allow for entire sections to be excluded from all business units. This is especially helpful for purpose-specific link pages, e.g. Edumate instance selection, IT links, Staff links. Unit tags using the Exclude and Only allow for school-specific exemptions or overrides in the **schools** sections, e.g. FACTS shortcuts for Brindabella and Hope or excluding Box of Books for schools who do not license it.

---

## Scripts (`.js`)

### `build.js` — generate the site

```shell
node build.js
```

Reads the three `_data/` files and writes `/<code>/index.html` for every unit. It also normalises `shortcuts.json` (sorts sections and entries) in place, so shortcuts are always populated on the link page in alphabetical order. Pass `--relative` to emit relative asset paths for opening the generated pages directly from disk (for testing only):

```shell
node build.js --relative
```

### `edit-shortcuts.js` — visual shortcut editor

```shell
node edit-shortcuts.js
```

Starts a local web app (opens `http://localhost:4173`) for adding, editing, reordering and deleting shortcuts without hand-editing JSON. It reads section labels from `sections.json` and unit codes from `units.json`, supports both icon types, and writes changes back to `shortcuts.json`. Press `Ctrl+C` in the terminal to stop it.

Icon files that exist at the time of the web app launch are read for path autocompletion but new icons added while it's running are not.

---

## Editing content directly

All changes are made in `_data/`, then committed and rebuilt.

- **Add a business unit:** append an object to `units.json` with a new unique `code`. Run the build — a `/<code>/` page is created automatically. Set appropriate `tags` so the right sections appear.
- **Add a section:** add an entry to `sections.json` (unique `id`, a `label`, optional `only`/`exclude`), then add a matching key in `shortcuts.json` holding its shortcuts. A section with no visible shortcuts won't render.
- **Add a shortcut:** add an entry to the relevant section's array in `shortcuts.json`. Use `icon` for a text tile or `icon_src` for an image, and optionally scope it with `only`/`exclude`.

After editing, run `node build.js` to regenerate the unit pages.

---

## Committing changes with Git (Windows Terminal)

From the project folder in Windows Terminal:

```powershell
# See what you've changed
git status

# Stage everything (or name specific files instead of .)
git add .

# Commit with a message
git commit -m "Add Intune shortcut to ms-portals"

# Send it to the remote (e.g. GitHub) — triggers the Static Web App deploy
git push
```

Typical loop: edit JSON → `node build.js` → `git add .` → `git commit -m "..."` → `git push`. Run `git pull` first if others may have made changes.
