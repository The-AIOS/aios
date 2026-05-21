---
name: sovra-web-design
description: "Sovra web design system — use when building or reviewing any Sovra web page, component, or web app. Encodes brand tokens, section patterns, animation cookbook, theming rules, product identities, and i18n conventions from sovra.io."
user-invocable: true
metadata:
  author: chuycepeda
  version: "1.0.0"
---

# Sovra Web Design System

## When to Use

- Building a new page or section on sovra.io or any Sovra web property
- Creating components that need to match Sovra brand
- Reviewing/auditing existing pages for design consistency
- Building admin interfaces within the Sovra ecosystem
- Any web content (landing pages, dashboards, tools) under the Sovra brand

## Design Tokens

### Colors

**Dark Theme (default):**

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#0099ff` | Buttons, links, accents |
| Primary Dark | `#2060df` | Hover states |
| Background | `#0a0915` | Page background (very dark purple-black) |
| Surface | `#0f0d1a` | Card/section backgrounds |
| Surface Hover | `#1a1725` | Interactive surface states |
| Text Primary | `#ffffff` | Headings, body text |
| Text Secondary | `#888888` | Captions, labels |
| Text Muted | `rgba(255,255,255,0.6)` | Supplementary text |
| Border | `rgba(255,255,255,0.05)` | Dividers, card borders |

**Light Theme:**

| Token | Value | Usage |
|-------|-------|-------|
| Background | `#f8f9fa` | Page background |
| Surface | `#ffffff` | Card/section backgrounds |
| Primary | `#0077cc` | Darker blue for light-bg contrast |
| Text Primary | `#1a1a2e` | Headings, body text |

### Product Color Identities

Each Sovra product has a distinct color. Never mix product colors across products.

| Product | Color | Hex | Used In |
|---------|-------|-----|---------|
| **SovraGov** | Blue | `#0099ff` | Blue gradients, badges, hero accents |
| **SovraWallet** | Purple | `#8b5cf6` | Purple gradients, badges, hero accents |
| **SovraID** | Green | `#22c55e` | Green gradients, badges, hero accents |
| **SovraChain** | Orange | `#f97316` | Orange gradients, badges, hero accents |

See `references/product-colors.md` for full gradient and badge specifications.

### Typography

| Role | Font | Usage |
|------|------|-------|
| Display | Plus Jakarta Sans | Headings, titles, hero text |
| Body | Figtree | Paragraphs, UI text, descriptions |
| Mono | JetBrains Mono | Code snippets, labels, badges |

Font loading uses `next/font/google` with `display: "swap"` for performance.

### Spacing

| Token | Value | Usage |
|-------|-------|-------|
| Section padding | `py-24` | Vertical rhythm between sections |
| Container gutters | `px-4 sm:px-6 lg:px-8` | Responsive horizontal padding |
| Card gaps | `gap-6` | Standard grid gaps |
| Card gaps (spacious) | `gap-8` | Looser layouts |
| Max-width narrow | `max-w-4xl` | Text-heavy content |
| Max-width standard | `max-w-7xl` | Default content width |
| Max-width wide | `max-w-400` | Edge-to-edge / wide layouts |

## CRITICAL: Theming Rules

**NEVER use Tailwind `dark:` variants.** The Sovra site uses class-based theming with `.light` overrides.

```css
/* CORRECT -- light mode override */
.light .my-component {
  background: #f8f9fa;
  color: #1a1a2e;
}

/* WRONG -- never do this */
<div className="dark:bg-black bg-white" />
```

How it works:

- Theme is stored in `localStorage` key `sovra-theme`
- The `<html>` element receives `.dark` or `.light` class
- Dark theme is the default -- code dark-first, then add `.light` overrides
- All light mode rules use the `.light .class-name` selector pattern
- Admin panel uses `data-admin-panel` attribute for style isolation: `.light [data-admin-panel]` rules

## Section Blueprint

Every section follows this layered anatomy:

```tsx
<section className="py-24 bg-dark-surface relative overflow-hidden section-fade-top">
  {/* Layer 1: Decorative backgrounds */}
  <div className="absolute inset-0 gradient-mesh-subtle" />
  <div className="absolute inset-0 grid-pattern" />

  {/* Layer 2: Optional floating orbs (hidden on mobile) */}
  <div className="absolute top-0 right-0 w-96 h-96 bg-primary/5 rounded-full blur-3xl hidden md:block" />

  {/* Layer 3: Content */}
  <Container>
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.6 }}
    >
      {/* Badge -> Title -> Description -> Content -> CTA */}
    </motion.div>
  </Container>
</section>
```

### Key CSS Classes

| Class | Effect |
|-------|--------|
| `gradient-mesh-subtle` | Radial gradient overlay with brand colors at low opacity |
| `gradient-mesh-primary` | Stronger version for hero sections |
| `grid-pattern` | 40px grid lines at 2% opacity |
| `section-fade-top` | 120px gradient fade at the top edge |
| `section-fade-bottom` | 120px gradient fade at the bottom edge |
| `glass` | `rgba(10,9,21,0.7)` + `backdrop-filter: blur(20px)` frosted overlay |

See `references/section-templates.md` for copy-paste section templates.

## Animation Cookbook

### Pattern 1: Scroll Reveal

Used on every section for fade-in-up on scroll:

```tsx
<motion.div
  initial={{ opacity: 0, y: 20 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true }}
  transition={{ duration: 0.6 }}
>
  {children}
</motion.div>
```

### Pattern 2: Staggered Children

For grids and lists where items appear one after another:

```tsx
<motion.div
  initial="hidden"
  whileInView="visible"
  viewport={{ once: true }}
  variants={{
    visible: { transition: { staggerChildren: 0.15 } },
  }}
>
  {items.map((item) => (
    <motion.div
      key={item.id}
      variants={{
        hidden: { opacity: 0, y: 20 },
        visible: { opacity: 1, y: 0 },
      }}
    />
  ))}
</motion.div>
```

### Pattern 3: Button Hover/Tap

Micro-interaction for all interactive elements:

```tsx
<motion.button
  whileHover={{ scale: 1.02 }}
  whileTap={{ scale: 0.98 }}
/>
```

Primary buttons also get the `btn-glow-pulse` class for animated `box-shadow` on hover.

### Pattern 4: 3D Tilt (Product Cards)

Perspective-based tilt with glare effect:

```tsx
import { useTilt3D } from "@/hooks/useTilt3D";

const { ref, style, glareStyle, handlers } = useTilt3D({
  maxTilt: 8,
  glareOpacity: 0.15,
  scale: 1.02,
  transitionSpeed: 600,
});
```

Details:
- `perspective(1000px)` + `rotateX`/`rotateY` based on mouse position
- Glare gradient follows cursor direction
- Automatically disabled on touch devices

### Pattern 5: Auto-Scroll Carousel

Continuous horizontal scroll using `useMotionValue` + `requestAnimationFrame`:

| Carousel Type | Speed | Card Width |
|---------------|-------|-----------|
| Testimonials | 0.5px/frame | 400px |
| Logos | 0.3px/frame | 180px |

Drag snapping uses spring physics: `stiffness: 300, damping: 30`.

### Pattern 6: Floating Elements

Ambient background orbs with infinite keyframe loops:

```tsx
<motion.div
  animate={{ y: [0, -40, 20, -10, 0] }}
  transition={{ duration: 25, repeat: Infinity, ease: "easeInOut" }}
/>
```

Stagger multiple orbs with different durations (25s, 30s, 22s) to avoid synchronized movement.

## Component Reference

### Button

```tsx
import { Button } from "@/components/ui/Button";

<Button variant="primary" size="lg" href="/demo">Try It Live</Button>
<Button variant="secondary" size="md">Learn More</Button>
<Button variant="outline" size="sm">Details</Button>
```

| Prop | Options | Notes |
|------|---------|-------|
| `variant` | `primary`, `secondary`, `outline` | Primary = filled blue, Secondary = subtle, Outline = border only |
| `size` | `sm`, `md`, `lg` | |
| `href` | string | Handles internal (Link) and external (a) routing automatically |

All buttons use `rounded-full` (pill shape).

### Container

```tsx
import { Container } from "@/components/ui/Container";

<Container>Standard content</Container>
<Container size="narrow">Text-heavy content</Container>
<Container size="wide">Edge-to-edge content</Container>
```

### HeroBackground

```tsx
import { HeroBackground } from "@/components/ui/HeroBackground";

<HeroBackground page="knowledge" />
```

Available page configs: `knowledge`, `case-studies`, `about`, `partners`, `newsroom`, `manifesto`, `press-kit`, `hiring`, `id-index`. Each has custom orb colors matching the page topic.

### Accordion

```tsx
import { Accordion } from "@/components/ui/Accordion";
```

Badge-aware: maps categories to accent colors automatically.

| Category | Color |
|----------|-------|
| General | Blue |
| Technical | Purple |
| Privacy | Emerald |
| Implementation | Amber |

## Page Recipe: Building a New Sovra Page

Follow this checklist in order:

1. **Create route:** `src/app/[locale]/your-page/page.tsx` + `layout.tsx`
2. **Add metadata** in `layout.tsx` (title, description, OG image)
3. **Use HeroBackground** with a page-specific color config
4. **Structure sections** following the Section Blueprint above
5. **Add translations** to ALL THREE files: `en.json`, `es.json`, `pt-BR.json`
6. **Add route to nav** if needed (`Header.tsx` dropdown or footer links)
7. **Test themes:** Toggle dark/light mode, verify all `.light` overrides work
8. **Test responsive:** Mobile (375px), Tablet (768px), Desktop (1280px)
9. **Test i18n:** Switch to ES and PT-BR, verify layout does not break with longer strings

## i18n Checklist

- Use `useTranslations("namespace")` from `next-intl`
- Config: 3 locales (`en`, `es`, `pt-BR`), default `en`, prefix `as-needed`
- **Product names ALWAYS stay in English:** SovraGov, SovraID, SovraWallet, SovraChain
- Spanish: informal "tu" form, conversational LATAM tone (Mexican, NOT Argentine "vos")
- Portuguese: "voce" form, professional Brazilian Portuguese
- Update ALL three translation files when changing any UI text
- Proper accents always: a, e, i, o, u, n, u, ?, !

## Anti-Patterns (Things That Break Consistency)

1. **Using `dark:` Tailwind variants** -- always use `.light .class` CSS overrides
2. **Forgetting `gradient-mesh` or `grid-pattern`** on sections -- they create the signature depth
3. **Missing `section-fade-top`/`section-fade-bottom`** -- sections should blend, not have hard edges
4. **Hardcoding colors** instead of using CSS custom properties
5. **Skipping floating orbs on desktop** -- they are part of the brand's ambient feel
6. **Using wrong product colors** -- each product has ONE color identity (see product-colors.md)
7. **Mixing product names** -- "SovraWallet" not "Sovra Wallet", "SovraGov" not "Sovra Gov"
8. **Forgetting mobile** -- hide floating elements below `md`, test touch for tilt
9. **Not testing light mode** -- many developers forget to check light mode after building in dark
10. **Inline styles for theming** -- use CSS custom properties and `.light` overrides

## Key Files Reference

| File | Purpose |
|------|---------|
| `src/app/globals.css` | All tokens, gradients, animations, theme overrides |
| `src/context/ThemeContext.tsx` | Dark/light mode provider |
| `src/components/ui/Button.tsx` | Primary button with Framer Motion |
| `src/components/ui/Container.tsx` | Layout wrapper (narrow/default/wide) |
| `src/components/ui/HeroBackground.tsx` | Page hero with animated orbs |
| `src/hooks/useTilt3D.ts` | 3D tilt + glare for cards |
| `src/components/sections/Products.tsx` | Product grid with 3D cards + badges |
| `src/components/sections/CTA.tsx` | CTA with glow button + trust indicators |
| `src/i18n/routing.ts` | i18n config (3 locales) |
