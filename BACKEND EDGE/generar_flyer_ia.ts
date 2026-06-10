import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

// ─── Catálogo de estilos ────────────────────────────────────────────────────
// Cada estilo define:
//   colorGrading     → paleta y tratamiento de color
//   backgroundStyle  → técnica/estética del fondo ilustrado
//   layoutArch       → disposición espacial, jerarquía tipográfica y contenedores
//   intensifyHint    → instrucción extra para la variante B (imagen 2)

const FILTER_PROMPTS: Record<string, {
  colorGrading: string;
  backgroundStyle: string;
  layoutArch: string;
  intensifyHint: string;
}> = {

  // ── Dark Night ──────────────────────────────────────────────────────────────
  dark_night: {
    colorGrading: "COLOR GRADING: deep blacks dominate 80% of the palette, dramatic high-contrast shadows, powerful warm-white and amber spotlights cutting through darkness, cinematic chiaroscuro, rich dark tones with isolated bright accents, professional nightclub atmosphere",
    backgroundStyle: "BACKGROUND STYLE: hyper-realistic cinematic photography aesthetic, sharp foreground details dissolving into atmospheric dark depth, volumetric fog catching stage lights, realistic dramatic lighting and deep shadows, premium nightclub or concert venue feel",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: title is 3x larger than all other text elements — it must dominate
- TITLE PLACEMENT: centered, upper-third zone, massive bold metallic chrome sans-serif ALL CAPS, strong drop shadow, slight inner glow effect, letter-spacing tight
- TITLE SIZE: enormous — takes up roughly 35% of image width
- DATE ELEMENT: small elegant pill badge just below title, semi-transparent dark background with thin white border, date text in clean light sans-serif
- CLAIM/SUBTITLE: centered below title, significantly smaller than title, medium-weight sans-serif in white or light grey, max 2 lines
- LINEUP SECTION (if provided): bold white sans-serif names, medium size, centered, between claim and footer
- PROMOTIONS FOOTER: dark glassmorphism container (frosted dark glass effect, subtle border), promotions text in bright white bold, positioned at bottom 20%
- SPONSORS ROW (if provided): very small monochrome white logos in a horizontal row, bottom edge of image
- OVERALL FEEL: professional nightclub event poster, premium modern design 2025-2026 standard`,
    intensifyHint: "VARIANT B INTENSIFICATION: push contrast to maximum, add dramatic lens flare effects cutting across the frame, make title chrome effect more pronounced with stronger metallic sheen, increase spotlight intensity, add subtle grain texture overlay for depth",
  },

  // ── Neon Party ──────────────────────────────────────────────────────────────
  neon_party: {
    colorGrading: "COLOR GRADING: pure black background base, electric neon palette — hot pink, cyan, electric green, purple, UV reactive colors only, maximum saturation on glow elements, zero warm tones, everything glows like actual neon tubes or UV light",
    backgroundStyle: "BACKGROUND STYLE: photorealistic UV neon environment, actual neon tube signs and LED strips as set dressing, laser beams and UV fog, realistic glow and light bleed on surfaces, neon reflections on wet or shiny floors, electric nightclub atmosphere",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: broken-grid layout — asymmetric and energetic, not centered but intentionally off-balance
- TITLE PLACEMENT: large, slightly off-center left or right, neon tube light typography effect — glowing colored outline with dark fill or transparent, neon flicker aesthetic, ALL CAPS grotesque or display font
- TITLE SIZE: very large, dominant, color matches one of the neon accent colors
- DATE ELEMENT: rotated slightly (5–10 degrees), neon color pill or tag shape, placed upper-right or lower-left breaking the grid intentionally
- CLAIM/SUBTITLE: smaller, neon outline text or plain white, placed opposite side of title for visual tension
- LINEUP SECTION (if provided): stacked vertically on one side, each name in a different neon accent color, medium-bold
- PROMOTIONS FOOTER: neon-bordered rectangular container, dark fill, promotion text in electric white or cyan
- SPONSORS ROW (if provided): flat neon-colored logos, small, in a row at absolute bottom
- OVERALL FEEL: 2025-2026 underground rave poster aesthetic, kinetic broken-grid layout, professional rave culture design`,
    intensifyHint: "VARIANT B INTENSIFICATION: add more neon light streaks cutting diagonally across the composition, intensify UV glow bloom on all neon elements, add laser grid perspective lines in background, push saturation to absolute maximum",
  },

  // ── Sunset Party ────────────────────────────────────────────────────────────
  sunset_party: {
    colorGrading: "COLOR GRADING: warm golden hour palette exclusively — peach, coral, amber, soft orange, dusty rose, no cold tones at all, natural sunlight color temperature, cinematic warm film look, soft glowy highlights",
    backgroundStyle: "BACKGROUND STYLE: photorealistic warm outdoor or rooftop photography aesthetic, golden hour cinematography with beautiful shallow depth of field, warm bokeh, sunflare or lens flare integrated naturally, airy and inviting atmosphere",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: elegant, airy, minimal — everything breathes, no clutter
- DATE ELEMENT: positioned in HEADER (top 12% of image), small clean sans-serif or thin serif, warm white or cream, centered — date leads the composition
- TITLE PLACEMENT: centered in the middle third, large elegant serif or semi-bold cursive-influenced font, warm white or soft gold, gentle text shadow for legibility
- TITLE SIZE: prominent but not aggressive — refined, takes upper-center focus
- CLAIM/SUBTITLE: below title, smaller italic serif or light sans-serif, cream colored, relaxed line-height
- LINEUP SECTION (if provided): elegant centered list below claim, thin weight font, cream or warm white, tasteful spacing
- PROMOTIONS FOOTER: minimal — subtle warm-white semi-transparent pill or soft underline only, small text, refined
- SPONSORS ROW (if provided): very small, cream-toned monochrome logos, centered, bottom edge with breathing space
- OVERALL FEEL: premium outdoor festival or rooftop event, editorial magazine quality, modern 2025 minimal warm aesthetic`,
    intensifyHint: "VARIANT B INTENSIFICATION: stronger golden hour lens flare sweeping across image, warmer color grade pushing toward rich amber, add more romantic bokeh in background, subtle grain texture for film feel",
  },

  // ── Cinematic ───────────────────────────────────────────────────────────────
  cinematic: {
    colorGrading: "COLOR GRADING: Hollywood teal-and-orange complementary color grading, rich desaturated shadows with teal undertones, warm orange highlights on skin and light sources, cinematic film grain, anamorphic stretch bokeh, premium movie color science",
    backgroundStyle: "BACKGROUND STYLE: cinematic movie poster photography — deep foreground elements with soft epic background, anamorphic lens flare effect, dual-exposure or composite feel, shallow depth of field, IMAX-quality compositional depth, film poster aesthetic",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: movie poster architecture — epic, layered, cinematic depth
- TITLE PLACEMENT: title text appears to be EMBEDDED IN THE SCENE — partially behind foreground elements (layered depth effect), centered or upper-third, creates 3D integration with the image
- TITLE STYLE: elegant refined serif or high-quality condensed sans-serif, cream or warm white, subtle letterpress or emboss effect, NOT floating on top but integrated into scene depth
- TITLE SIZE: very large but elegant, not aggressive
- DATE ELEMENT: small, horizontal letterpress-style text below title, thin tracking, cream color — like a movie release date treatment
- CLAIM/SUBTITLE: italic serif below title, significantly smaller, one line maximum, warm cream
- LINEUP SECTION (if provided): centered elegant names, medium weight, tracking-expanded, below claim
- PROMOTIONS FOOTER: thin horizontal rule separator, promotion text in small refined serif, warm-toned minimal container
- SPONSORS ROW (if provided): very small sepia or cream-tinted logos in a row, centered, separated by thin vertical rules
- OVERALL FEEL: A-list movie premiere poster quality, award-worthy cinematic design, 2025 premium event aesthetic`,
    intensifyHint: "VARIANT B INTENSIFICATION: increase anamorphic lens flares dramatically, push teal-orange contrast further, add more cinematic film grain texture, deepen shadows for maximum drama",
  },

  // ── Caricature ──────────────────────────────────────────────────────────────
  caricature: {
    colorGrading: "COLOR GRADING: vibrant saturated cartoon palette — rich primaries and secondaries, warm festive energy, no dark moody tones, everything bright and fun, Nickelodeon or modern animated series color energy",
    backgroundStyle: "BACKGROUND STYLE: professional 2D cartoon illustration style with clean linework, flat colors with cel-shading, comic book panel aesthetic, bold outlines on all elements, hand-drawn feel with digital precision, dynamic cartoon action lines",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: fun and bold — cartoon energy in every element
- TITLE PLACEMENT: large cartoon bubble letters or bold display font centered or slightly off-center, thick black outline on every letter, slight 3D extrusion effect, colorful fill
- TITLE SIZE: very large, playful, takes up dominant space
- DATE ELEMENT: cartoon starburst or explosion badge shape, bright fill with contrasting text, positioned dynamically (upper corner or beside title at angle)
- CLAIM/SUBTITLE: fun bold sans-serif below title, smaller, with cartoon speech bubble or wavy underline decoration
- LINEUP SECTION (if provided): each name in a different bright color, cartoon bold, stacked or scattered playfully
- PROMOTIONS FOOTER: cartoon banner ribbon at bottom — bright colored with contrasting bold text, wavy or torn edge style
- SPONSORS ROW (if provided): cartoon-style logo rendering, small and colorful at absolute bottom
- OVERALL FEEL: modern animated cartoon event poster, professional illustration quality, fun and inviting for all ages`,
    intensifyHint: "VARIANT B INTENSIFICATION: add more cartoon action lines and speed effects, increase saturation to absolute maximum, add confetti and stars scattered throughout, make outlines even bolder",
  },

  // ── Funny & Color ────────────────────────────────────────────────────────────
  funny_color: {
    colorGrading: "COLOR GRADING: maximum saturation explosion — every primary and secondary color present, rainbow energy, zero dark tones, everything at highest brightness, pop art Roy Lichtenstein meets modern party aesthetics",
    backgroundStyle: "BACKGROUND STYLE: hyper-colorful photorealistic party scene, confetti and streamers raining everywhere, bright studio-quality lighting, multiple colored light sources, festive maximum-energy atmosphere, everything is celebratory",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: chaos with intention — maximum visual energy, color blocking as layout tool
- TITLE PLACEMENT: MASSIVE centered typography using color-blocking technique — each word or letter on a different solid color band, ultra-bold grotesque ALL CAPS
- TITLE SIZE: enormous, takes up 40% of image width, cannot be missed
- DATE ELEMENT: bright contrasting color pill badge, possibly rotated slightly, upper area or overlapping title
- CLAIM/SUBTITLE: different bright color band, bold, below title
- LINEUP SECTION (if provided): rainbow-colored names list, each in different vivid color, bold centered
- PROMOTIONS FOOTER: bright solid color horizontal band at bottom (contrasting), white bold text, celebration energy
- SPONSORS ROW (if provided): flat multicolor logos, small, within footer band
- OVERALL FEEL: maximum celebration energy, Gen-Z party aesthetics 2025, bold colorful professional party design`,
    intensifyHint: "VARIANT B INTENSIFICATION: add more confetti layers, push colors to neon territory, add holographic shine effect on title letters, multiply light sources for maximum brightness",
  },

  // ── Gourmet Warm ────────────────────────────────────────────────────────────
  gourmet_warm: {
    colorGrading: "COLOR GRADING: soft natural light palette exclusively — cream, warm white, linen, light wood tones, muted sage green, no harsh contrasts, Scandinavian editorial warmth, like a premium food magazine",
    backgroundStyle: "BACKGROUND STYLE: photorealistic editorial food or venue photography, soft diffused natural window light, minimal clean composition, light wood grain or white marble textures, artisan handcrafted aesthetic, premium restaurant atmosphere",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: minimal, editorial, every element has breathing space
- DATE ELEMENT: top header area, very small clean sans-serif or thin serif in warm brown, left-aligned or centered — sets premium editorial tone
- TITLE PLACEMENT: centered in middle third, large elegant serif typeface (think Playfair Display style), warm brown or dark cream color, generous line-height if multi-line
- TITLE SIZE: prominent but restrained — editorial refined, not aggressive
- CLAIM/SUBTITLE: below title, small italic serif in muted warm tone, one or two short lines maximum
- LINEUP SECTION (if provided): small elegant centered text, thin weight, warm brown, tasteful vertical spacing
- PROMOTIONS FOOTER: extremely minimal — thin horizontal rule in warm tone, small serif text below, no colored containers, refinement over loudness
- SPONSORS ROW (if provided): tiny monochrome warm-toned logos centered, separated by small dots or rules, bottom of image
- OVERALL FEEL: premium gastronomic event poster, editorial sophistication, modern fine dining or food festival aesthetic 2025`,
    intensifyHint: "VARIANT B INTENSIFICATION: softer more dreamlike light quality, increase warmth and creaminess of color grade, add soft grain texture for film photography feel, tighter crop on hero food or venue element",
  },

  // ── Wood & Fine ─────────────────────────────────────────────────────────────
  wood_fine: {
    colorGrading: "COLOR GRADING: deep rich dark palette — dark walnut brown, aged bourbon amber, forest green accents, candlelight warm gold, deep burgundy, zero cold tones, luxury low-key lighting like a private members club",
    backgroundStyle: "BACKGROUND STYLE: photorealistic premium fine dining or private club photography, dramatic candlelight as primary light source, dark rich aged wood grain textures prominently featured, crystal and glassware details with warm reflections, bokeh warm candlelight background",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: old-money luxury — restrained but commanding
- TITLE PLACEMENT: centered upper area, classic high-contrast serif font (think Garamond bold or Bodoni style), gold metallic foil effect with subtle emboss, ALL CAPS with generous letter-spacing
- TITLE SIZE: large but dignified — not aggressive, powerful through weight and finish rather than size
- DATE ELEMENT: wax seal or letterpress badge below title, circular or oval shape, dark fill with gold border, small refined date text inside
- CLAIM/SUBTITLE: small italic serif below date badge, cream or warm gold color, centered, one line
- LINEUP SECTION (if provided): centered gold text, thin weight, expanded tracking, elegant vertical list
- PROMOTIONS FOOTER: dark panel at bottom (continuation of background), gold foil rule separating from image, promotion text in small gold serif, laurel wreath or ornamental dividers
- SPONSORS ROW (if provided): gold monochrome logos, very small, separated by small ornamental dots, centered in footer panel
- OVERALL FEEL: private members club event invitation, Michelin-starred dinner announcement, old-money luxury aesthetic, premium 2025 fine event design`,
    intensifyHint: "VARIANT B INTENSIFICATION: deeper richer shadows, more pronounced gold metallic shine on title, additional candlelight lens flare, increase leather and aged wood texture detail",
  },

  // ── Tropical Fiesta ─────────────────────────────────────────────────────────
  tropical_fiesta: {
    colorGrading: "COLOR GRADING: explosive Latin fiesta palette — vibrant coral red, hot orange, tropical yellow gold, electric lime green accents, maximum warm saturation, Argentine cuarteto and cumbia visual energy, festive and loud",
    backgroundStyle: "BACKGROUND STYLE: photorealistic festive tropical party photography, warm saturated lighting with multiple colored light sources, confetti and streamers integrated into scene, high-energy crowd silhouettes in background, tropical flowers or decorations as set dressing",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: maximum Latin fiesta energy — loud, proud, festive
- TITLE PLACEMENT: centered and LARGE, bold 3D extruded letters with gold or orange metallic finish, Latin festival typography style, slight arc or curve to lettering optionally, strong drop shadow
- TITLE SIZE: enormous, takes up 40% of width, festive and unmissable
- DATE ELEMENT: sunburst or starburst badge shape with yellow-gold fill and contrasting dark text, positioned above or flanking the title dynamically
- CLAIM/SUBTITLE: bold contrasting color text below title, energetic, short
- LINEUP SECTION (if provided): bold colorful stacked names, each in warm accent color, centered with festive energy
- PROMOTIONS FOOTER: bright horizontal banner at bottom, orange or red fill, white bold ALL CAPS text, festive pattern or confetti border
- SPONSORS ROW (if provided): flat warm-colored logos in a row, bottom edge
- OVERALL FEEL: Argentine popular fiesta event poster, cuarteto/cumbia visual tradition, modern 2025 Latin party aesthetics, professional and festive`,
    intensifyHint: "VARIANT B INTENSIFICATION: more confetti explosions, push color saturation to absolute maximum warm territory, add fireworks or sparkle effects in background, bolder 3D extrusion on title",
  },

  // ── Urban Street ────────────────────────────────────────────────────────────
  urban_street: {
    colorGrading: "COLOR GRADING: raw urban palette — concrete grey base with aggressive spray paint accent colors (toxic green, hot pink, electric yellow, chrome silver), high contrast street aesthetic, authentic worn city color patina",
    backgroundStyle: "BACKGROUND STYLE: photorealistic urban texture environment, actual concrete walls with layered graffiti tags and street art, worn poster layers peeling to reveal previous posters, authentic alley or underpass atmosphere, gritty authentic street culture setting",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: street poster tradition — raw, layered, intentionally rough
- TITLE PLACEMENT: large graffiti-style lettering or ultra-heavy grotesque ALL CAPS, slightly rotated or imperfectly placed (intentional imprecision), spray paint drip effects on letters, positioned upper-center or breaking out of grid
- TITLE SIZE: very large, aggressive, street presence
- DATE ELEMENT: stencil-style lettering, slightly off-angle, spray-painted look, upper area or overlapping title edge — raw placement intentional
- CLAIM/SUBTITLE: different spray paint color from title, rough placement below title, bold and direct
- LINEUP SECTION (if provided): stacked raw bold text, different colors, like a bill posting wall — multiple layers of information
- PROMOTIONS FOOTER: torn-paper or ripped-edge visual effect at bottom edge, revealing a bright solid color layer beneath with promotion text in stencil style
- SPONSORS ROW (if provided): black stencil-style logos at absolute bottom, rough alignment
- OVERALL FEEL: authentic underground hip-hop or street art event poster, professional street culture design 2025, broken-grid anti-layout aesthetic`,
    intensifyHint: "VARIANT B INTENSIFICATION: add more spray paint splatter effects, increase weathering and wear texture on all surfaces, add more overlapping layers of torn posters, push the raw anti-design energy further",
  },

  // ── Golden Luxury ───────────────────────────────────────────────────────────
  golden_luxury: {
    colorGrading: "COLOR GRADING: ultra-exclusive black and gold palette only — pure deep black, rich 24-karat gold, champagne highlights, zero other colors whatsoever, maximum luxury contrast, like Cartier or Louis Vuitton brand aesthetics",
    backgroundStyle: "BACKGROUND STYLE: photorealistic premium luxury material textures — black Marquina marble with prominent gold veining, crystal champagne glass details, gold leaf particles floating, deep reflective black surfaces, ultra-premium exclusive atmosphere",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: old-world luxury meets modern premium — commanding and exclusive
- TITLE PLACEMENT: centered upper-third, classic serif typography with gold metallic foil treatment and emboss effect, generous letter-spacing, commanding presence without shouting
- TITLE SIZE: large and stately — power through quality not volume
- DATE ELEMENT: centered below title, enclosed in elegant gold-bordered rectangular container (thin gold rule top and bottom, no fill), date in small premium serif, gold color
- CLAIM/SUBTITLE: small italic gold serif below date container, one line, centered, refined
- LINEUP SECTION (if provided): gold text names centered, expanded tracking, thin weight, elegant vertical spacing
- PROMOTIONS FOOTER: gold foil horizontal rule separating footer, dark panel (continuation of marble texture), promotion text in small gold serif, flanked by ornamental gold diamond or fleur motifs
- SPONSORS ROW (if provided): gold monochrome premium logos, very small, centered, separated by thin gold vertical rules
- OVERALL FEEL: exclusive gala event invitation, luxury brand event design, Michelin-star party aesthetic, ultra-premium 2025 luxury design`,
    intensifyHint: "VARIANT B INTENSIFICATION: increase gold particle density in background, stronger gold metallic sheen on all text, add subtle gold light shaft from above, deepen blacks for higher luxury contrast",
  },

  // ── Retro Vintage ───────────────────────────────────────────────────────────
  retro_vintage: {
    colorGrading: "COLOR GRADING: authentic aged print palette — faded desaturated warm yellows, dusty pinks, muted sky blues, paper cream background tones, ink printing imperfection colors, Risograph or screen-print color aesthetic, deliberate fading and aging",
    backgroundStyle: "BACKGROUND STYLE: aged paper texture with authentic wear — fold creases, water stains, foxing spots, printing misregistration, overlapping vintage poster layers, early 2000s Argentine disco/boliche poster tradition, screen-print aesthetic",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: vintage poster tradition — asymmetric, layered, typographically rich
- TITLE PLACEMENT: large retro display font — multiple weights and sizes stacked (like vintage gig posters), slight misregistration on letters for authentic print feel, warm ink color, not perfectly centered — intentional asymmetry
- TITLE SIZE: dominant but using stacking and variation rather than one big word
- DATE ELEMENT: vintage rubber stamp or seal aesthetic, circular or rectangular with worn border, positioned overlapping other elements — feels aged and authentic
- CLAIM/SUBTITLE: different vintage font from title, smaller, italic or condensed, aged paper color
- LINEUP SECTION (if provided): stacked gig-poster style — bigger names bigger text, smaller names smaller, all vintage fonts, like a vintage concert bill
- PROMOTIONS FOOTER: horizontal band with worn texture, vintage ink color, promotion text in period-appropriate typeface
- SPONSORS ROW (if provided): vintage halftone or letterpress-style logos, aged tones, bottom of poster
- OVERALL FEEL: authentic late-90s early-2000s Argentine boliche poster made with modern quality, vintage underground music poster tradition, Risograph print aesthetic 2025`,
    intensifyHint: "VARIANT B INTENSIFICATION: increase paper aging and wear dramatically, more visible fold lines and stains, stronger misregistration effect on typography, deeper color fading for maximum vintage authenticity",
  },

  // ── Epic Stage ──────────────────────────────────────────────────────────────
  epic_stage: {
    colorGrading: "COLOR GRADING: Hollywood action blockbuster color science — aggressive teal-orange complementary grading, intense warm pyrotechnic highlights, cold steel-blue shadows, maximum cinematic drama, Michael Bay or Zack Snyder color intensity",
    backgroundStyle: "BACKGROUND STYLE: photorealistic epic concert or stadium stage photography, heroic low-angle camera perspective looking UP at stage, pyrotechnics explosions and fire columns, massive crowd in background with phone lights creating sea of light, smoke haze catching colored beams, EPIC scale",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: action movie poster architecture — heroic, powerful, EPIC
- TITLE PLACEMENT: centered, MASSIVE ALL CAPS OBLIGATORY, metallic chrome or steel effect with fire/energy texture, strong perspective foreshortening if possible (letters appearing to rush toward viewer), major drop shadow with orange glow
- TITLE SIZE: enormous — takes up nearly full width, undeniable presence
- DATE ELEMENT: horizontal metallic TORN or RIPPED PAPER visual effect — as if the image is physically torn to reveal the date information on a different layer underneath, metallic torn edge detail, date text beneath in bold clean font
- CLAIM/SUBTITLE: ALL CAPS bold condensed, metallic silver or white, below torn date element, dramatic
- LINEUP SECTION (if provided): bold ALL CAPS metallic names, stacked with hierarchy — headliners bigger, supports smaller, chrome effect throughout
- PROMOTIONS FOOTER: heavy dark metallic panel, riveted or industrial edge detail, promotion text in bold white ALL CAPS, orange or red accent for urgency
- SPONSORS ROW (if provided): metallic monochrome logos, industrial styling, bottom of metallic footer panel
- OVERALL FEEL: stadium-scale event poster, world-tour concert design quality, maximum epic cinematic impact, professional 2025 large-scale event aesthetic`,
    intensifyHint: "VARIANT B INTENSIFICATION: add more pyrotechnic explosion columns, increase fire and smoke volume dramatically, stronger chrome metallic effect on title, add shockwave or energy blast radiating from title",
  },

  // ── Pixar World ─────────────────────────────────────────────────────────────
  pixar_world: {
    colorGrading: "COLOR GRADING: rich magical Pixar/Disney color depth — warm magical amber and blue complementary balance, subsurface scattering warmth, cinematic 3D render lighting with multiple colored light sources, Disney feature film color science, enchanting and inviting",
    backgroundStyle: "BACKGROUND STYLE: Pixar-quality 3D CGI environment render — smooth rounded surfaces with subsurface scattering, expressive stylized realism, cinematic depth with foreground mid-ground background separation, magical light particles or sparkles, Disney/Pixar feature film production quality",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: Disney movie marquee — magical, grand, family-friendly epic
- TITLE PLACEMENT: centered, large 3D inflated bubble letters with glossy finish (like Pixar movie title cards), letters cast shadows into the scene naturally, warm glow emanating from title, anchored in upper-center-to-middle zone
- TITLE SIZE: very large — Pixar movie title treatment, must feel like a real Disney/Pixar movie poster
- DATE ELEMENT: positioned CLOSE to title (just below), small but charming — like a movie release date treatment: "NOW SHOWING — [date]" in clean rounded font, subtle magical sparkle around it
- CLAIM/SUBTITLE: rounded playful font below date, smaller, warm and inviting tone, slight 3D treatment matching title
- LINEUP SECTION (if provided): centered rounded font, medium size, each name with a small magical sparkle or star indicator
- PROMOTIONS FOOTER: smooth rounded banner shape at bottom (integrated into scene as 3D element — like a banner held by characters or hanging from scene), bright color fill with white rounded bold text
- SPONSORS ROW (if provided): flat or slightly 3D logos in warm monochrome, small, in the footer banner area
- OVERALL FEEL: Pixar feature film premiere poster quality, magical entertainment event design, Disney-quality production aesthetic 2025`,
    intensifyHint: "VARIANT B INTENSIFICATION: more magical sparkle particles throughout scene, increase subsurface scattering warmth on all 3D surfaces, add more whimsical floating elements (bubbles, stars, lights), richer magical atmosphere",
  },

  // ── NEW: Synthwave / Retrowave ───────────────────────────────────────────────
  synthwave: {
    colorGrading: "COLOR GRADING: authentic 80s synthwave palette — hot magenta, electric purple, neon cyan, deep indigo background, chrome silver accents, retrowave sunset gradient (purple to hot pink to orange on horizon), Miami Vice color DNA",
    backgroundStyle: "BACKGROUND STYLE: synthwave retrowave 3D aesthetic — receding grid lines vanishing to horizon point (perspective grid on ground plane), retro 80s sun with horizontal line segments on horizon, neon palm tree silhouettes, chrome chrome wireframe shapes, night sky with stars or space nebula, VHS scan lines texture overlay",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: 80s retrofuture movie poster meets modern design
- TITLE PLACEMENT: centered, large chrome or neon-outlined retro display font (think Stranger Things or Miami Vice typography DNA), strong perspective or slight 3D extrusion, magenta or cyan glow aura, positioned upper-center above the horizon line
- TITLE SIZE: large and cinematic, retro-bold
- DATE ELEMENT: positioned ON the horizon or just above the retrowave grid, chrome metallic pill or retro-arcade badge shape, magenta or cyan fill
- CLAIM/SUBTITLE: below title, synthwave italic or condensed font, neon outline style, cyan or pink
- LINEUP SECTION (if provided): retro arcade score-style listing — each name on its own line in chrome or neon font, centered, like a high score board
- PROMOTIONS FOOTER: VHS tape or cassette-inspired horizontal band at bottom, scan line texture on the band, promotion text in retro-pixel or chrome font
- SPONSORS ROW (if provided): neon-outlined small logos at bottom of footer band
- OVERALL FEEL: premium retrowave event poster, Stranger Things meets Drive movie aesthetic, 80s retrofuturism done with 2025 quality and professionalism`,
    intensifyHint: "VARIANT B INTENSIFICATION: stronger VHS scan line texture overlay on entire image, more intense horizon glow, add chromatic aberration effect on title edges, deeper space/nebula background, increase neon intensity",
  },

  // ── NEW: Minimal Ibiza ───────────────────────────────────────────────────────
  minimal_ibiza: {
    colorGrading: "COLOR GRADING: ultra-minimal white and one accent palette — 90% white or off-white cream, single accent color (warm terracotta, sage green, or deep navy, chosen contextually), maximum negative space, luxury minimalism",
    backgroundStyle: "BACKGROUND STYLE: single high-quality editorial photograph or clean abstract texture — white or cream backdrop with one striking visual element (architectural detail, single flower, abstract shape), premium magazine photography quality, lots of clean empty space, light and airy",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: luxury minimalism — every element isolated and intentional, negative space is a design element
- DATE ELEMENT: HEADER position at very top (top 8%), small clean sans-serif or ultra-thin serif in accent color, centered — minimal and elegant
- TITLE PLACEMENT: centered in middle zone, large elegant serif typeface (editorial weight, like Vogue or Harper's Bazaar masthead), dark color (near-black or deep tone), generous letter-spacing
- TITLE SIZE: large but refined — presence through quality not volume
- CLAIM/SUBTITLE: small italic serif below title, muted tone, perfectly minimal, maximum one line
- LINEUP SECTION (if provided): small elegant centered names, ultra-thin font weight, accent color, generous spacing between entries
- PROMOTIONS FOOTER: single thin horizontal rule line at bottom zone, below the rule: minimal small sans-serif text in muted tone — no containers or colored backgrounds whatsoever
- SPONSORS ROW (if provided): extremely small logos, muted monochrome, centered, absolute bottom with generous breathing space
- OVERALL FEEL: Ibiza or Mykonos premium event invitation, architectural digest event quality, ultra-luxury minimal 2025 design, high-fashion event aesthetic`,
    intensifyHint: "VARIANT B INTENSIFICATION: even more extreme negative space, reduce additional elements further, increase contrast of single accent element, add ultra-fine grain texture for premium paper feel",
  },

  // ── NEW: Brutalist Type ──────────────────────────────────────────────────────
  brutalist_type: {
    colorGrading: "COLOR GRADING: stark brutalist palette — pure black and pure white as base, maximum contrast, one optional accent color (raw red, electric yellow, or pure cobalt), no gradients, no soft tones, binary contrast only",
    backgroundStyle: "BACKGROUND STYLE: brutalist architectural photography or pure solid color — raw concrete, exposed structure, industrial geometry, OR pure black/white solid background where TYPOGRAPHY IS THE ENTIRE VISUAL — no decorative illustration needed",
    layoutArch: `LAYOUT & TYPOGRAPHY ARCHITECTURE:
- VISUAL HIERARCHY: TYPOGRAPHY IS THE DESIGN — text layout creates the visual composition entirely
- TITLE PLACEMENT: massive ultra-heavy grotesque ALL CAPS (Swiss International style, Helvetica Neue Black or Impact DNA), full-bleed edge to edge if possible, stark black on white OR white on black, absolutely no decorative effects — pure type power
- TITLE SIZE: ENORMOUS — fills 50-60% of image width, brutally present, impossible to ignore
- DATE ELEMENT: stark contrasting placement — black bar or rule with white text reversed out, or pure white box with black text, positioned bluntly (could be over the title, could be rotated 90 degrees on side margin)
- CLAIM/SUBTITLE: drastically smaller than title (emphasizing hierarchy through extreme size contrast), ultra-heavy or ultra-thin (no middle weights — go to extremes), positioned bluntly
- LINEUP SECTION (if provided): tabular layout like a newspaper listing, heavy rule separators, monospaced or grotesque font, stark black and white
- PROMOTIONS FOOTER: solid black or red bar at bottom, white reversed-out text, no ornaments, brutally direct
- SPONSORS ROW (if provided): stark monochrome logos in stark alignment, ruled separators between them
- OVERALL FEEL: underground Berlin techno event poster, Bauhaus tradition meets 2025 design, Swiss grid brutalism, professional anti-decoration aesthetic, intellectual and confrontational`,
    intensifyHint: "VARIANT B INTENSIFICATION: increase type size even further until letters bleed off edges, add one strong red accent element, increase grain texture on background, maximize the stark black-white contrast",
  },
};

// ─── Constructor de prompt ──────────────────────────────────────────────────
// Todos los campos opcionales solo se incluyen si tienen contenido real.

function buildPrompt(params: {
  titulo: string;
  claim: string;
  diaSemana: string;
  fecha: string;        // e.g. "Sábado 12 de Julio" or "Viernes 11 y Sábado 12 de Julio"
  hora: string;
  fondoDescripcion: string;
  estiloPropio: string | null;
  estiloId: string;
  // Opcionales
  promos: string | null;
  lineup: string | null;
  sponsors: string | null;
  dresscode: string | null;
  // Variante B
  isVariantB?: boolean;
}): string {
  const filtro = FILTER_PROMPTS[params.estiloId] ?? FILTER_PROMPTS["dark_night"];

  const estiloTexto = params.estiloPropio
    ? `CUSTOM STYLE OVERRIDE: ${params.estiloPropio}`
    : "";

  // Secciones opcionales — solo se incluyen si tienen contenido real
  const lineupSection = params.lineup?.trim()
    ? `\nLINEUP / ARTISTS: ${params.lineup.trim()}`
    : "";

  const promosSection = params.promos?.trim()
    ? `\nPROMOTIONS: ${params.promos.trim()}`
    : "";

  const sponsorsSection = params.sponsors?.trim()
    ? `\nSPONSORS (draw recognizable brand logos, small, at bottom): ${params.sponsors.trim()}`
    : "";

  const dresscodeSection = params.dresscode?.trim()
    ? `\nDRESS CODE: ${params.dresscode.trim()}`
    : "";

  const variantBInstruction = params.isVariantB
    ? `\n\nVARIANT DIRECTION: ${filtro.intensifyHint}`
    : "";

  return `Create a PROFESSIONAL EVENT FLYER — portrait 9:16 format, ultra-high resolution, print and social media ready.
Modern professional design 2025-2026 standard. Visually striking, commercially attractive, ready to share on Instagram Stories.

═══ SCENE & BACKGROUND ═══
${params.fondoDescripcion}
${filtro.backgroundStyle}

═══ COLOR & ATMOSPHERE ═══
${filtro.colorGrading}

═══ LAYOUT, TYPOGRAPHY & HIERARCHY ═══
${filtro.layoutArch}
${estiloTexto ? `\n${estiloTexto}` : ""}

═══ TEXT CONTENT TO RENDER ═══
MAIN TITLE: "${params.titulo}"
CLAIM/TAGLINE: "${params.claim}"
DATE & TIME: "${params.diaSemana} ${params.fecha} — ${params.hora}hs"${lineupSection}${promosSection}${dresscodeSection}${sponsorsSection}

═══ CRITICAL RULES ═══
- All text content must appear EXACTLY as written above — in Spanish as provided, no translation
- Do NOT add any text, watermarks, website URLs, or placeholder text not listed above
- If a section is not listed above, do NOT invent content for it or add "PROMOTIONS:" without promotions
- Background scene fills entire frame — no white borders or padding
- Final result must look like a REAL professional event flyer that could be printed or posted on Instagram today
- Quality benchmark: indistinguishable from a professional graphic designer's work${variantBInstruction}`;
}

/** Modo prompt libre: solo indica 9:16 + reglas técnicas; el creativo lo define el usuario. */
function buildPromptLibre(params: {
  promptLibre: string;
  isVariantB?: boolean;
}): string {
  const variantBInstruction = params.isVariantB
    ? `\n\nVARIANT B INTENSIFICATION: alternate creative angle with stronger visual impact, richer contrast and composition, while staying faithful to the user's description.`
    : "";

  return `Create a PROFESSIONAL EVENT FLYER — mandatory portrait 9:16 aspect ratio, ultra-high resolution, print and social media ready (Instagram Stories / Reels / WhatsApp status).
Modern professional event flyer design standard 2025-2026. Visually striking and commercially attractive.

═══ TECHNICAL FLYER REQUIREMENTS (always apply) ═══
- Portrait vertical 9:16 format, full bleed edge-to-edge, no white borders or padding
- Clear typographic hierarchy: main title dominant, secondary info readable
- All text in Spanish exactly as described by the user — do not translate
- Background fills entire frame; professional event poster quality
- Do NOT add watermarks, website URLs, QR codes, or placeholder text unless the user asked for them
- Do NOT invent promotions, lineup, sponsors, or dates not described by the user

═══ USER CREATIVE DIRECTION (follow faithfully) ═══
${params.promptLibre.trim()}${variantBInstruction}`;
}

// ─── Subir imagen al Storage de Supabase ───────────────────────────────────

async function subirImagenAlStorage(
  supabase: ReturnType<typeof createClient>,
  supabaseUrl: string,
  grokUrl: string,
  generacionId: string,
  index: number,
): Promise<string> {
  const imgResp = await fetch(grokUrl);
  if (!imgResp.ok) throw new Error(`No se pudo descargar imagen ${index} de Grok`);

  const arrayBuffer = await imgResp.arrayBuffer();
  const uint8 = new Uint8Array(arrayBuffer);
  const storagePath = `${generacionId}/${index}.jpg`;

  const { error: uploadError } = await supabase.storage
    .from("flyers-ia")
    .upload(storagePath, uint8, { contentType: "image/jpeg", upsert: true });

  if (uploadError) throw new Error(`Storage upload error [${index}]: ${uploadError.message}`);

  const { data: publicData } = supabase.storage
    .from("flyers-ia")
    .getPublicUrl(storagePath);

  return publicData.publicUrl;
}

// ─── Edge principal ─────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { ok: false, error: "Metodo no permitido" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const xaiApiKey = Deno.env.get("api_key_de_grok") ?? "";

    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(500, { ok: false, error: "Configuracion incompleta del servidor" });
    }
    if (!xaiApiKey) {
      return jsonResponse(500, { ok: false, error: "API key de IA no configurada" });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse(401, { ok: false, error: "Token invalido o ausente" });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const accessToken = authHeader.replace("Bearer ", "").trim();

    const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
    if (authError || !authData.user) {
      return jsonResponse(401, { ok: false, error: "No autenticado" });
    }
    const uid = authData.user.id;

    let body: unknown;
    try { body = await req.json(); } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, error: "Body invalido" });
    }

    const modoRaw           = String(body.modo ?? "estructurado").trim().toLowerCase();
    const esModoLibre       = modoRaw === "libre" || modoRaw === "prompt_libre";
    const generacionPadreId = body.generacion_padre_id ? String(body.generacion_padre_id).trim() : null;

    let titulo            = String(body.titulo ?? "").trim();
    let claim             = String(body.claim ?? "").trim();
    let diaSemana         = String(body.dia_semana ?? "").trim();
    let fecha             = String(body.fecha ?? "").trim();
    let hora              = String(body.hora ?? "").trim();
    let fondoDesc         = String(body.fondo_descripcion ?? "").trim();
    let estiloId          = String(body.estilo_id ?? "dark_night").trim();
    let estiloPropio      = body.estilo_propio ? String(body.estilo_propio).trim() : null;
    const promptLibre     = String(body.prompt_libre ?? "").trim();

    // Campos opcionales (solo modo estructurado)
    const promos   = body.promos   ? String(body.promos).trim()   : null;
    const lineup   = body.lineup   ? String(body.lineup).trim()   : null;
    const sponsors = body.sponsors ? String(body.sponsors).trim() : null;
    const dresscode = body.dresscode ? String(body.dresscode).trim() : null;

    let estiloNombreDb = estiloId;
    let promptA: string;
    let promptB: string;

    if (esModoLibre) {
      if (!promptLibre) {
        return jsonResponse(400, { ok: false, error: "prompt_libre requerido" });
      }
      if (promptLibre.length > 1000) {
        return jsonResponse(400, { ok: false, error: "prompt_libre maximo 1000 caracteres" });
      }
      if (!titulo) titulo = promptLibre.slice(0, 80);
      estiloNombreDb = "prompt_libre";
      promptA = buildPromptLibre({ promptLibre, isVariantB: false });
      promptB = buildPromptLibre({ promptLibre, isVariantB: true });
    } else {
      if (!titulo)    return jsonResponse(400, { ok: false, error: "titulo requerido" });
      if (!claim)     return jsonResponse(400, { ok: false, error: "claim requerido" });
      if (!fondoDesc) return jsonResponse(400, { ok: false, error: "fondo_descripcion requerido" });
      if (!FILTER_PROMPTS[estiloId]) return jsonResponse(400, { ok: false, error: "estilo_id invalido" });

      const promptBase = { titulo, claim, diaSemana, fecha, hora, fondoDescripcion: fondoDesc, estiloPropio, estiloId, promos, lineup, sponsors, dresscode };
      promptA = buildPrompt({ ...promptBase, isVariantB: false });
      promptB = buildPrompt({ ...promptBase, isVariantB: true });
    }

    const esRetry = generacionPadreId !== null;

    const { data: perfil, error: perfilError } = await supabase
      .from("perfiles_locales")
      .select("cupos_flyers_ia, flyer_generando, flyer_generando_desde")
      .eq("id", uid)
      .single();

    if (perfilError || !perfil) {
      return jsonResponse(404, { ok: false, error: "Perfil de local no encontrado" });
    }

    // Verificar lock con timeout de 90 segundos
    if (perfil.flyer_generando) {
      const desde = perfil.flyer_generando_desde ? new Date(perfil.flyer_generando_desde) : null;
      const segundos = desde ? (Date.now() - desde.getTime()) / 1000 : 999;
      if (segundos < 90) {
        return jsonResponse(429, {
          ok: false,
          code: "generacion_en_curso",
          error: "Ya hay una generacion en curso. Esperá unos segundos.",
        });
      }
      console.log(`generar_flyer_ia: lock timeout para uid=${uid}, liberando`);
    }

    if (esRetry) {
      const { data: padre, error: padreError } = await supabase
        .from("flyer_generaciones")
        .select("id, retry_usado, created_at, local_id, es_retry")
        .eq("id", generacionPadreId)
        .single();

      if (padreError || !padre) {
        return jsonResponse(404, { ok: false, error: "Generacion padre no encontrada" });
      }
      if (padre.local_id !== uid) {
        return jsonResponse(403, { ok: false, error: "No autorizado" });
      }
      if (padre.es_retry) {
        return jsonResponse(400, { ok: false, code: "retry_no_permitido", error: "No se puede reintentar una generacion que ya es un reintento" });
      }
      if (padre.retry_usado) {
        return jsonResponse(400, { ok: false, code: "retry_ya_usado", error: "El reintento gratis ya fue usado" });
      }
      const minutos = (Date.now() - new Date(padre.created_at).getTime()) / 60000;
      if (minutos > 10) {
        return jsonResponse(400, { ok: false, code: "retry_expirado", error: "El tiempo para reintentar gratis expiró (10 minutos)" });
      }
    } else {
      if (perfil.cupos_flyers_ia < 1) {
        return jsonResponse(402, { ok: false, code: "sin_creditos", error: "Sin creditos de Flyers IA disponibles" });
      }

      const inicioDia = new Date();
      inicioDia.setHours(0, 0, 0, 0);
      const { count } = await supabase
        .from("flyer_generaciones")
        .select("id", { count: "exact", head: true })
        .eq("local_id", uid)
        .eq("es_retry", false)
        .gte("created_at", inicioDia.toISOString());

      if ((count ?? 0) >= 30) {
        return jsonResponse(429, { ok: false, code: "rate_limit", error: "Limite diario de 30 generaciones alcanzado" });
      }
    }

    // Activar lock
    await supabase
      .from("perfiles_locales")
      .update({ flyer_generando: true, flyer_generando_desde: new Date().toISOString() })
      .eq("id", uid);

    // Llamar a Grok dos veces en paralelo — una imagen por prompt
    let grokUrls: string[] = [];
    let urlsFinales: string[] = [];
    let errorMensaje: string | null = null;

    try {
      const callGrok = async (prompt: string): Promise<string> => {
        const resp = await fetch("https://api.x.ai/v1/images/generations", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${xaiApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "grok-imagine-image",
            prompt,
            n: 1,
            aspect_ratio: "9:16",
          }),
        });

        if (!resp.ok) {
          const errText = await resp.text();
          throw new Error(`Grok API error ${resp.status}: ${errText}`);
        }

        const data = await resp.json() as { data: { url: string }[] };
        if (!data.data?.[0]?.url) throw new Error("Grok no devolvio imagen");
        return data.data[0].url;
      };

      // Llamadas en paralelo para reducir tiempo de espera
      const [urlA, urlB] = await Promise.all([callGrok(promptA), callGrok(promptB)]);
      grokUrls = [urlA, urlB];

    } catch (grokError) {
      errorMensaje = grokError instanceof Error ? grokError.message : String(grokError);
      console.error("generar_flyer_ia: error grok", errorMensaje);

      await supabase
        .from("perfiles_locales")
        .update({ flyer_generando: false, flyer_generando_desde: null })
        .eq("id", uid);

      await supabase.from("flyer_generaciones").insert({
        local_id: uid,
        titulo,
        estilo_nombre: estiloNombreDb,
        prompt_usado: promptA,
        urls_generadas: [],
        es_retry: esRetry,
        generacion_padre_id: generacionPadreId,
        creditos_usados: 0,
        entregado: false,
        error_mensaje: errorMensaje,
      });

      return jsonResponse(502, { ok: false, code: "grok_error", error: "Error al generar imagenes. Intentá de nuevo." });
    }

    // Insertar en DB con URLs temporales de Grok
    const { data: generacion, error: insertError } = await supabase
      .from("flyer_generaciones")
      .insert({
        local_id: uid,
        titulo,
        estilo_nombre: estiloNombreDb,
        prompt_usado: promptA,
        urls_generadas: grokUrls,
        es_retry: esRetry,
        generacion_padre_id: generacionPadreId,
        creditos_usados: esRetry ? 0 : 1,
        entregado: false,
        error_mensaje: null,
      })
      .select("id")
      .single();

    if (insertError) throw insertError;
    const generacionId: string = generacion.id;

    // Subir las 2 imágenes al Storage en paralelo
    try {
      const uploads = await Promise.all(
        grokUrls.map((url, i) =>
          subirImagenAlStorage(supabase, supabaseUrl, url, generacionId, i)
            .catch((err) => {
              console.error(`generar_flyer_ia: fallo subida imagen ${i}:`, err);
              return url; // fallback a URL de Grok
            })
        )
      );
      urlsFinales = uploads;
    } catch {
      urlsFinales = grokUrls;
    }

    // Actualizar con URLs permanentes del Storage
    await supabase
      .from("flyer_generaciones")
      .update({ urls_generadas: urlsFinales })
      .eq("id", generacionId);

    // Actualizar créditos o marcar retry
    if (esRetry && generacionPadreId) {
      await supabase
        .from("flyer_generaciones")
        .update({ retry_usado: true })
        .eq("id", generacionPadreId);
    } else {
      await supabase
        .from("perfiles_locales")
        .update({ cupos_flyers_ia: perfil.cupos_flyers_ia - 1 })
        .eq("id", uid);
    }

    // Liberar lock
    await supabase
      .from("perfiles_locales")
      .update({ flyer_generando: false, flyer_generando_desde: null })
      .eq("id", uid);

    return jsonResponse(200, {
      ok: true,
      generacion_id: generacionId,
      urls: urlsFinales,
      creditos_restantes: esRetry ? perfil.cupos_flyers_ia : perfil.cupos_flyers_ia - 1,
    });

  } catch (error) {
    console.error("generar_flyer_ia_error", error);
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
