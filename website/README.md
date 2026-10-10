# ClickMore website

A static landing page based on Space Left’s dark split layout, system typography, blue download button, and compact footer. The right-hand panel is an interactive illustration of ClickMore’s four-button test board, not a screenshot or a connection to the desktop. Clicks are slowed for clarity; reduced-motion mode updates the counters immediately.

Preview from the repository root:

```sh
python3 -m http.server 8099 --directory website --bind 127.0.0.1
```

Open `http://127.0.0.1:8099`. Deploy `website/` as a static directory; no build step, external fonts, or JavaScript dependencies are required. Set canonical and social page URLs once a hosting domain has been chosen.

The download button points to GitHub’s latest release, where visitors can choose the signed PKG installer or ZIP. It stays current without changing the website. Homebrew stays on the latest cask in `helgesverre/tap`.
