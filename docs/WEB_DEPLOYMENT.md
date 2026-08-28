# Biome Bloome Web deployment

The Web preset targets Godot 4.7.2 and produces a single-threaded, extension-free release for itch.io at `builds/web/index.html`. The single-threaded variant avoids cross-origin-isolation requirements and is the most compatible Godot Web configuration for an itch.io iframe.

## Build

From the repository root:

```sh
./scripts/build-web.sh
```

The script locates the Godot editor, requires the exact `4.7.2.stable.official.ed1daf0bf` build and its `web_nothreads_release.zip` template, performs a release export through Godot's CLI, and verifies the HTML, JavaScript, WebAssembly, and PCK artifacts before replacing `builds/web/`.

Set `GODOT_BIN` only when the matching editor is installed somewhere nonstandard. Set `GODOT_TEMPLATE_DIR` only when its templates are stored outside Godot's normal macOS user directory.

## One-command deployment

Butler requires an existing itch.io page and authenticated local account. Configure page identifiers once:

```sh
cp .itchio.env.example .itchio.env
```

Edit `.itchio.env`, then authenticate without putting credentials in the repository:

```sh
butler login
```

Future releases are built, checked with Butler's offline HTML5 validator, and pushed to the same itch.io channel with:

```sh
./scripts/deploy-web.sh
```

The deployment script validates the page identifiers and authentication before it builds or uploads. It then rebuilds the release and runs `butler push --if-changed builds/web <username>/<project>:html5`. No password, API key, or token belongs in `.itchio.env`.

For the first Butler upload, the existing itch.io page must be configured as an HTML game. Confirm that the `html5` upload is marked as playable in the browser, that its embed is 1280 by 800 (or uses fullscreen), and that the page remains non-public until you intentionally publish it.
