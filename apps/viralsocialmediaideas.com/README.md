# Viral Social Media Ideas

A simple tool that generates social media content ideas for musicians. Built with [Astro](https://astro.build) for maximum performance.

🔗 **Live:** [viralsocialmediaideas.com](https://viralsocialmediaideas.com)

## Features

- Instant idea generation with spacebar or button click
- Multi-language support (English, German, Spanish, French, Dutch, Chinese, Hindi)
- Static site generation for fast load times
- Zero JavaScript frameworks shipped to client

## Getting Started

```bash
npm install
npm run dev
```

Open [http://localhost:4321](http://localhost:4321) in your browser.

## Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Start development server |
| `npm run build` | Build for production |
| `npm run preview` | Preview production build |
| `npm run lint` | Check for linting issues |
| `npm run lint:fix` | Auto-fix linting issues |
| `npm run format` | Format all files |

## Project Structure

```
src/
├── layouts/
│   └── Layout.astro       # Base HTML layout
├── components/
│   ├── Nav.astro          # Navigation bar
│   └── RandomIdea.astro   # Idea generator
└── pages/
    ├── index.astro        # Landing page
    ├── idea.astro         # Idea generator (English)
    └── [lang]/            # Localized pages
        ├── index.astro
        └── idea.astro
dictionaries/              # Translated idea lists per locale
public/                    # Static assets
```

## Tech Stack

- [Astro](https://astro.build) - Static site generator
- [Tailwind CSS](https://tailwindcss.com) - Styling
- [Biome](https://biomejs.dev) - Linting & formatting

## Deployment

Build and deploy the `dist/` folder to any static hosting provider (Vercel, Netlify, Cloudflare Pages, etc.).

```bash
npm run build
```

---

Built by [Tapped AI](https://tapped.ai)
