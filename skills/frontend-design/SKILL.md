---
name: frontend-design
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, or applications. Generates creative, polished code that avoids generic AI aesthetics.
user-invocable: true
---

This skill guides creation of distinctive, production-grade frontend interfaces that avoid generic "AI slop" aesthetics. Implement real working code with exceptional attention to aesthetic details and creative choices.

The user provides frontend requirements: a component, page, application, or interface to build. They may include context about the purpose, audience, or technical constraints.

## Design Thinking

Before coding, understand the context and commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist chaos, retro-futuristic, organic/natural, luxury/refined, playful/toy-like, editorial/magazine, brutalist/raw, art deco/geometric, soft/pastel, industrial/utilitarian, etc.
- **Constraints**: Technical requirements (framework, performance, accessibility).
- **Differentiation**: What makes this UNFORGETTABLE? What's the one thing someone will remember?

**CRITICAL**: Choose a clear conceptual direction and execute it with precision. Bold maximalism and refined minimalism both work—the key is intentionality, not intensity.

Then implement working code (HTML/CSS/JS, React, Vue, etc.) that is:
- Production-grade and functional
- Visually striking and memorable
- Cohesive with a clear aesthetic point-of-view
- Meticulously refined in every detail

## Frontend Aesthetics Guidelines

### Typography

**NEVER use:** Inter, Roboto, Arial, Open Sans, Lato, system fonts, or any generic sans-serif defaults.

**DO use distinctive fonts like:**
- Display: Playfair Display, Bricolage Grotesque, Clash Display, Cabinet Grotesk, Satoshi
- Monospace: JetBrains Mono, Berkeley Mono, Geist Mono, IBM Plex Mono
- Serif: Newsreader, Literata, Source Serif Pro, Fraunces
- Sans: Plus Jakarta Sans, General Sans, Outfit, Syne

**Font pairing strategies:**
- Display + Monospace (editorial tech aesthetic)
- Serif + Geometric Sans (refined contrast)
- Heavy display + Light body (dramatic hierarchy)

**Typography ratios:**
- Use extreme weight variations: 100/200 for elegance vs 800/900 for impact
- Size jumps of 3x+ between hierarchy levels (e.g., 16px body → 56px heading)
- Don't be afraid of massive type (72px+) or tiny details (10px labels)

### Color & Theme

Commit to a cohesive aesthetic using CSS variables for consistency.

**Principles:**
- Dominant colors with sharp accents outperform timid, evenly-distributed palettes
- Draw inspiration from IDE themes (Dracula, Nord, Catppuccin, Rosé Pine, Tokyo Night)
- Reference cultural aesthetics (Japanese minimalism, Swiss design, Memphis, Bauhaus)
- Consider unconventional palettes: monochromatic with one pop color, earth tones, jewel tones

**NEVER:** Purple gradients on white backgrounds, generic blue CTAs, safe corporate palettes.

### Motion & Animation

Prioritize CSS-only solutions for HTML. Use Motion library (Framer Motion) for React when available.

**Focus on high-impact moments:**
- One well-orchestrated page load with staggered reveals (animation-delay) creates more delight than scattered micro-interactions
- Scroll-triggered animations that surprise
- Hover states with personality (scale, rotation, color shifts)
- Meaningful transitions between states

**Techniques:** Spring physics, cubic-bezier curves, staggered children, exit animations.

### Spatial Composition

Break expectations:
- Asymmetry over centered layouts
- Overlap and layering
- Diagonal flow and broken grids
- Generous negative space OR controlled density
- Full-bleed sections alternating with contained content

### Backgrounds & Visual Details

Create atmosphere and depth rather than defaulting to solid colors:
- Gradient meshes and multi-stop gradients
- Noise/grain textures (subtle, 2-5% opacity)
- Geometric patterns and SVG backgrounds
- Layered transparencies and glassmorphism
- Dramatic shadows (large blur, offset)
- Decorative borders and dividers
- Custom cursors for key interactions

## Anti-Patterns to Avoid

NEVER use generic AI-generated aesthetics:
- Overused font families (Inter, Roboto, Arial, Open Sans, Lato)
- Cliched color schemes (purple gradients, generic blue, safe grays)
- Predictable centered layouts with uniform spacing
- Cookie-cutter card grids with identical rounded corners
- Stock-photo hero sections
- Generic "AI slop" that lacks context-specific character

**WARNING:** Don't converge on "alternative defaults" either. Space Grotesk, for example, has become a new cliche. Vary your choices across projects.

## Implementation Notes

**Match complexity to vision:**
- Maximalist designs need elaborate code with extensive animations and effects
- Minimalist designs need restraint, precision, and careful attention to spacing, typography, and subtle details
- Elegance comes from executing the vision well

**Vary across generations:**
- No two designs should look the same
- Alternate between light and dark themes
- Use different font combinations each time
- Explore different aesthetic directions

Remember: Claude is capable of extraordinary creative work. Don't hold back—show what can truly be created when thinking outside the box and committing fully to a distinctive vision.
