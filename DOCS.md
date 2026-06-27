# CCM IT App Launcher — Documentation

A static site generator that produces a per–business-unit grid of app shortcuts. Content and structure lives in three JSON files under `_data/`; a build script turns them into one static HTML page per unit, while an editor script makes rapid editing simple.

---

## Data files (`_data/`)

### `units.json`

An array of business units. Each unit becomes its own page at `/<code>/`.

| Field            | Type   | Purpose                                                                                  |
| ---------------- | ------ | ---------------------------------------------------------------------------------------- |
| `code`           | string | Unique short code. **Also the output folder name** (e.g. `CCMIT`).                       |
| `name`           | string | Full display name (page title, logo alt text).                                           |
| `shortName`      | string | Short label shown in the top navigation bar.                                             |
| `accent`         | string | Hex accent colour for the page (e.g. `#22325d`).                                         |
| `logo`           | string | Root-relative path to the unit logo (e.g. `/logos/ccm-logo.png`).                        |
| `collegeAppsUrl` | string | URL for the "College Apps" link in the nav bar.                                          |
| `logoUrl`        | string | *(optional)* URL the logo links to. When set, the logo becomes a clickable link.         |
| `tags`           | array  | Tags used for **section** visibility (e.g. `["school"]`).                                |
| `sectionSplits`  | object | *(optional)* Split one section into multiple tabs for this unit. See **Section splits**. |

Current tags are:

- `school`
- `ccm-it`
- `edumate`
- `stafflauncher`

Example:

```jsonc
{
  "code": "CCMIT",
  "name": "CCM IT Services",
  "shortName": "CCM IT",
  "accent": "#22325d",
  "logo": "/logos/ccm-logo.png",
  "collegeAppsUrl": "https://ccmschools.app/go/",
  "logoUrl": "https://www.ccmschools.edu.au/",
  "tags": ["ccm-it"]
}
```

### `sections.json`

An array of sections — the filter tabs shown on each page.

| Field     | Type            | Purpose                                                                     |
| --------- | --------------- | --------------------------------------------------------------------------- |
| `id`      | string          | Unique id. **Must match a key in `shortcuts.json`** and is used as grid id. |
| `label`   | string          | Text on the filter/tab button.                                              |
| `only`    | string \| array | *(optional)* Show only for units whose `code` or `tags` match.              |
| `exclude` | string \| array | *(optional)* Hide for units whose `code` or `tags` match.                   |

A section only appears on a unit's page if it is visible for that unit **and** has at least one visible shortcut. If only one section is active, the filter row is hidden automatically.

Example:

```jsonc
{ "id": "support",    "label": "Technical Support", "only": ["school"]        },
{ "id": "ms-portals", "label": "Microsoft Portals", "only": ["ccm-it"]       }
```

### `shortcuts.json`

A top-level **object keyed by section `id`**. Each value is an array of shortcut entries.

```jsonc
{
  "ms-portals": [
    {
      "id": "intune",
      "href": "https://in.cmd.ms",
      "icon_src": "svg/microsoftIntune.svg",
      "label": "Intune"
    }
  ],
  "students": [
    {
      "id": "clickview",
      "href": "https://clickview.com.au",
      "icon_src": "svg/clickview.svg",
      "label": "ClickView",
      "groups": [
        "secondary"
      ]
    }
  ]
}
```

| Field      | Type   | Purpose                                                                                      |
| ---------- | ------ | -------------------------------------------------------------------------------------------- |
| `id`       | string | Identifier for the shortcut (unique within its section).                                     |
| `href`     | string | Link target.                                                                                 |
| `label`    | string | Text shown under the icon. Use `\|` to force a line break.                                   |
| `icon`     | string | **Text icon** — renders a coloured square containing this short text.                        |
| `icon_src` | string | **Image icon** — path under `icons/` (e.g. `svg/teams.svg`, `webp/edval.webp`).              |
| `bg`       | string | *(optional)* Background colour behind an image icon (hex or CSS colour name).                |
| `only`     | array  | *(optional, school sections only)* Show only for these unit **codes**.                       |
| `exclude`  | array  | *(optional, school sections only)* Show for all units **except** these codes.                |
| `groups`   | array  | *(optional)* Sub-group assignment for units with `sectionSplits`. See **Section splits**.    |
| `also`     | array  | *(optional)* Also render this shortcut in these additional section **ids**. See **Linking**. |

**Icon choice:** give a shortcut **either** `icon` (text tile) **or** `icon_src` (image) — not both. The graphical editor ensures this is handled.

**Visibility precedence:** `only`/`exclude` are applied **only in school sections** — in non-school sections every unit that can see the section sees the shortcut. Within a school section: if `only` is present it wins; otherwise `exclude` applies; otherwise the shortcut shows for every school. This is evaluated per section copy, so a shortcut shared into multiple sections via `also` can be open in one and restricted in another (see **Linking a shortcut to multiple sections**).

---

## Section splits (primary / secondary)

A unit can split any section into multiple tabs — for example, showing separate "Primary Students" and "Secondary Students" tabs instead of a single "Students" tab — without duplicating shortcuts or touching other units.

### How it works

**1. Configure the split on the unit** — add `sectionSplits` to the unit in `units.json`:

```jsonc
{
  "code": "livingstone",
  "sectionSplits": {
    "students": [
      {
        "id": "students-primary",
        "label": "Primary Students",
        "groups": [
          "primary"
        ]
      },
      {
        "id": "students-secondary",
        "label": "Secondary Students",
        "groups": [
          "secondary"
        ]
      }
    ]
  }
}
```

Each sub-tab has its own `id` (used as the HTML tab/grid id), a `label`, and a `groups` array declaring which shortcut group populates it.

**2. Tag shortcuts that belong to a specific sub-group** — add `groups` to individual shortcuts in `shortcuts.json`:

```jsonc
{ "id": "clickview",  ..., "groups": ["secondary"] },
{ "id": "reading-eggs", ..., "groups": ["primary"]  },
{ "id": "google-workspace", ... }
```

**Routing rules for a unit with a split active:**

| Shortcut has…             | Appears in…                        |
| ------------------------- | ---------------------------------- |
| No `groups` field         | **All** sub-tabs (shared shortcut) |
| `"groups": ["primary"]`   | Primary sub-tab only               |
| `"groups": ["secondary"]` | Secondary sub-tab only             |

**Units without `sectionSplits`** ignore the `groups` field entirely — they see a single combined tab with all shortcuts, exactly as before. Tagging a shortcut is non-destructive.

### Editor support

The shortcut editor (`edit-shortcuts.js`) automatically shows a **Sub-group** panel when at least one unit has `sectionSplits` configured. The available group values (e.g. "primary", "secondary") are derived from the `sectionSplits` in `units.json` — add a new group there and it appears in the editor without any code change.

---

## Linking a shortcut to multiple sections

By default a shortcut lives in exactly one section — the key it sits under in `shortcuts.json`. The optional `also` field renders the *same* shortcut in additional sections without duplicating it, so a single edit keeps every copy in sync.

```jsonc
"ccm-t1-services": [
  {
    "id": "owna",
    "href": "https://my.owna.com.au",
    "icon_src": "svg/owna.svg",
    "label": "Owna",
    "only": ["blakescrossing", "dalby"],
    "also": ["pandc"]
  }
]
```

The shortcut is authored once under its home section (`ccm-t1-services`); `also` lists the extra section **ids** it should also appear in (`pandc`).

**Interaction with `only`/`exclude`:** these filters are evaluated **per section copy**, and only in **school** sections. In the example above:

- The `ccm-t1-services` copy is in a non-school section, so `only` is ignored — every unit that sees that section sees Owna.
- The `pandc` copy is in a school section, so `only` applies — only Blakes Crossing and Dalby get Owna under Parents & Carers.

This lets a shortcut stay globally visible in its home section while being restricted to specific schools where it also appears.

### Editor support for `also`

The **Also appears in** panel lists every section; tick the ones a shortcut should be copied into. A section that receives a shortcut via `also` shows those incoming shortcuts in its list with a `↳ from:` source label — clicking one jumps to its home section for editing.

---

## Combining unit and section tags for shortcut visibility

Section `only`/`exclude` tags control which units see an entire section (e.g. keeping `ms-portals` away from school pages). Shortcut-level `only`/`exclude` handle school-specific overrides within a school section (e.g. FACTS shortcuts for Brindabella only, or removing Box of Books for non-subscribers); they are ignored in non-school sections. A shortcut can appear in more than one section via `also` — see **Linking a shortcut to multiple sections**.

---

## Scripts

### `build.js` — generate the site

```shell
node build.js
```

Reads the three `_data/` files and writes `/<code>/index.html` for every unit. It also normalises `shortcuts.json` (sorts sections and entries alphabetically) in place. Pass `--relative` to emit relative asset paths for opening the generated pages directly from disk (testing only):

```shell
node build.js --relative
```

### `edit-shortcuts.js` — visual shortcut editor

```shell
node edit-shortcuts.js
```

Starts a local web app at `http://localhost:4173` for adding, editing, reordering and deleting shortcuts without hand-editing JSON. Features:

- **Two-stage section selector** — choose a group first (Schools, CCM IT, Edumate, Staff Launcher — derived from section tags), then pick a section within it.
- **Also appears in** — tick additional sections to copy a shortcut into via `also`. Incoming copies show in a section's list with a `↳ from:` source label.
- **Sub-group panel** — appears when any unit has `sectionSplits` configured; lets you assign shortcuts to primary/secondary (or other groups defined in `units.json`).
- **Unit visibility** — Only / Exclude checklists. They take effect only for the copies of a shortcut that land in a school section.
- **Icon preview** — live preview for both text tiles and image icons.
- **Reload** — re-read the `_data/` files and `icons` folder from disk.

Press `Ctrl+C` in the terminal to stop it. Icon files present at launch are read for path autocompletion; icons added while it's running require a reload to appear in suggestions, but manually typed paths still render a preview.

---

## Editing content directly

All changes are made in `_data/`, then rebuilt and committed.

- **Add a business unit:** append an object to `units.json` with a new unique `code`. Run the build — a `/<code>/` page is created automatically. Set appropriate `tags` so the right sections appear. Set `logoUrl` to make the logo a link to the school's public website.
- **Add a section:** add an entry to `sections.json` (unique `id`, a `label`, optional `only`/`exclude`), then add a matching key in `shortcuts.json` holding its shortcuts. A section with no visible shortcuts won't render.
- **Add a shortcut:** add an entry to the relevant section's array in `shortcuts.json`. Use `icon` for a text tile or `icon_src` for an image, and optionally scope it with `only`/`exclude`. Put a `\|` in the `label` to force a line break.
- **Show a shortcut in more than one section:** add an `also` array listing the extra section ids — see **Linking a shortcut to multiple sections**.
- **Set up a primary/secondary split:** add `sectionSplits` to the unit in `units.json`, then tag individual shortcuts in that section with `groups` as needed. Untagged shortcuts appear in all sub-tabs automatically.

After editing, run `node build.js` to regenerate the unit pages.

---

## Committing changes with Git

```shell
# See what you've changed
git status

# Stage everything (or name specific files instead of .)
git add .

# Commit with a message
git commit -m "Add ClickView to secondary students group"

# Send it to the remote — triggers the Static Web App deploy
git push
```

Typical loop: edit JSON → `node build.js` → `git add .` → `git commit -m "..."` → `git push`. Run `git pull` first if others may have made changes.

---

## Appendix: business units and their sections

A snapshot of what each unit's page currently renders, taken from the `_data/` files on 2026-06-27. A section appears only if it is tagged for the unit **and** has at least one visible shortcut, so this list reflects actual output rather than what is merely configured. Regenerate it after significant content changes.

### Schools (`school`)

All sixteen school units render the same three sections:

- Students
- Parents & Carers
- Technical Support

Units: Blakes Crossing, Brindabella, Chinchilla, Cornerstone, Dalby, Dunsborough, Endeavour, Groves, Hope, Rivers, Seaview, Staines Memorial, The Lakes, Warwick, Whitsunday.

**Livingstone Christian College** is the exception — it splits Students into sub-tabs via `sectionSplits`:

- Students › Primary
- Students › Secondary
- Parents & Carers
- Technical Support

### Edumate Student Information System (`edumate`)

- Edumate

### CCM Staff Apps (`stafflauncher`)

- General
- Educational Resources
- School Administration
- Support
- Service Requests

### CCM IT Services (`ccm-it`)

- Microsoft Portals
- Managed Platforms
- Enabled Platforms
- Other
