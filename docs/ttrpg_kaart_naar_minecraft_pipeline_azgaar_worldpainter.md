# Handleiding: Van Bestaande TTRPG-Kaart naar Minecraft Wereld

**Doelstelling:** Het 1-op-1 vertalen van de fysieke Heldengilde TTRPG-spelwereld naar de Minecraft-server. 
**Pedagogische Meerwaarde (Duidelijkheid = Veiligheid):** Door dezelfde wereld, steden en verhaallijnen te gebruiken aan zowel de fysieke D&D-tafel als op de Minecraft-server, ontstaat een voorspelbaar ankerpunt. Jongeren die online een woud of ruïne hebben verkend, herkennen deze direct tijdens een fysieke sessie (en andersom). Dit verlaagt de drempel van *Online $\rightarrow$ Fysieke Ontmoeting* aanzienlijk.

---

## Overzicht van de Pipeline

```
[Bestaande TTRPG Kaart (PNG/JPG)] 
       │
       ▼ (Stap 1 & 2: Opschonen & Image Converter)
[Azgaar's Fantasy Map Generator (.map)]  ──► Genereert ontbrekende rivieren, biomen, wegen & dorpen
       │
       ▼ (Stap 3: Hoogtekaart & Overlay Exporteren + ImageMagick Smooth)
[16-bit / Smooth Heightmap + Overlay PNG]
       │
       ▼ (Stap 4: WorldPainter Import & Custom Layers)
[Minecraft Wereld (/data/world)]         ──► Klaar voor Pelican Volume, Chunky & MythicDungeons
```

---

## Stap 1: De Bestaande TTRPG-Kaart Voorbereiden

Azgaar's *Image Converter* leest de kleurwaarden van pixels om te bepalen wat oceaan, vlakte of gebergte is. Tekstlabels, rasters (grids) of kompasrozen op de afbeelding worden anders aangezien voor bergketens in de vorm van letters.

1. **Bronbestand beschikbaar (Inkarnate, Wonderdraft, Photoshop/GIMP):**
   * Schakel de lagen met **tekstlabels**, **stad-icoontjes**, **hex/square grids** en **kaders** tijdelijk uit.
   * Exporteer een "kale" versie van het landschap als `ttrpg-base-clean.png` (bij voorkeur minimaal `2048x2048` of `4096x4096` pixels).
   * Exporteer daarnaast één versie **mét** alle namen en steden als `ttrpg-reference.png` (om straks naast je scherm te houden).
2. **Alleen een platte afbeelding (met tekst) beschikbaar:**
   * Geen probleem! Gebruik de afbeelding zoals hij is. In Stap 2 strijk je de kleine "tekst-bobbeltjes" in 30 seconden glad met de *Heightmap Brush* in Azgaar.

---

## Stap 2: Inladen in Azgaar & Details Laten Aanvullen

Azgaar gebruikt jullie landvormen als basis en berekent vervolgens op natuurkundig logische wijze waar rivieren stromen, welke biomen waar ontstaan en waar kleinere dorpen en handelsroutes liggen.

1. Open [Azgaar's Fantasy Map Generator](https://azgaar.github.io/Fantasy-Map-Generator/).
2. **Zet de resolutie maximaal (Cruciaal vóór het importeren):**
   * Ga linksboven naar het menu ($\equiv$) $\rightarrow$ **Options**.
   * Zet **Points number (cells)** op **`100K`**. Hoe meer cellen Azgaar berekent, hoe vloeiender je kustlijnen en bergen straks in Minecraft worden.
   * Stel **Canvas size** in op een vierkante of passende verhouding (bijv. `4096 x 4096`).
3. **Start de Image Converter:**
   * Ga naar het tabblad **Tools** $\rightarrow$ klik onder het kopje *Heightmap* op **Edit**.
   * Kies in de waarschuwings-popup voor **Erase** (dit wist alle oude data zodat Azgaar straks rivieren en biomen 100% opnieuw berekent op basis van jullie kaart).
   * Klik in het gereedschapsmenu op **Image Converter** en upload `ttrpg-base-clean.png`.
4. **Kleuren Koppelen aan Hoogtes (Elevation Mapping):**
   * Klik op **Auto-assign colors** (of koppel de kleuren handmatig):
     * **Diepblauw / Lichtblauw (Oceaan & Kustwater):** Hoogte `< 20` (in Azgaar is `20` het zeeniveau).
     * **Groen / Geel (Laagland, Stranden, Vlaktes):** Hoogte `21 – 45`.
     * **Lichtbruin / Donkergroen (Heuvels & Hoogland):** Hoogte `46 – 69`.
     * **Donkerbruin / Grijs / Wit (Bergketens & Pieken):** Hoogte `70 – 100`.
   * *Tip bij ingebakken tekst:* Zie je na de conversie oneffenheden waar tekst stond? Gebruik linksboven de **Paint Brushes** (*Smooth* of *Flatten*) om die plekjes even glad te vegen.
5. **Genereer de Wereld-Details:**
   * Klik rechtsboven op **Complete**.
   * Azgaar berekent nu automatisch:
     * **Rivieren & Meren:** Stromend vanaf jullie bergketens naar de zee.
     * **Biomen:** Bossen, moerassen, toendra's en woestijnen op basis van wind en bergschaduw.
     * **Burgs (Steden/Dorpen) & Routes (Wegen):** Automatisch gegenereerde handelswegen en gehuchtjes.
6. **Jullie Bestaande TTRPG-Steden Vastleggen:**
   * Ga naar **Tools** $\rightarrow$ **Burgs** (of klik direct op een stad op de kaart) om de belangrijkste steden te hernoemen naar jullie echte TTRPG-steden en ze naar de exacte positie te slepen.
   * Laat de kleinere gegenereerde dorpjes en ruïnes ertussenin lekker staan: dit geeft de **Verkenners** in Minecraft nieuwe plekken om te ontdekken die tóch passen in de lore!
7. **Sla het bronbestand op:**
   * Ga naar **Save** $\rightarrow$ download het **`.map` bestand** en commit dit in jullie repository (`heldengilde-content/world-design/`).

---

## Stap 3: Exporteren uit Azgaar & "Terracing" Voorkomen

Om de kaart in WorldPainter in te laden, hebben we twee exact even grote PNG-afbeeldingen nodig uit Azgaar: de **Hoogtekaart (Heightmap)** en de **Referentie-Overlay**.

### A. Export 1: De Monochrome Heightmap
1. Ga in Azgaar naar **Layers**: zet **alle knoppen uit** (geen Borders, geen Routes, geen Rivers, geen Labels, geen Icons, geen Grid).
2. Klik alleen de laag **Heightmap** aan.
3. Ga naar **Style** $\rightarrow$ selecteer bij *Element* de optie **Heightmap** $\rightarrow$ zet *Color scheme* op **Monochrome** (Zwart = diepste oceaanbodem, Wit = hoogste bergtop).
4. Zet onder **Options** de **Scale / Resolution** zo dat de export bijvoorbeeld exact `4096 x 4096` of `8192 x 8192` pixels is *(in Minecraft is 1 pixel = 1 blok; `4096x4096` is een mooie, overzichtelijke wereld van 4 bij 4 km)*.
5. Klik op **Export** $\rightarrow$ **PNG** en sla op als `azgaar-heightmap-raw.png`.

### B. Export 2: De Wegen, Rivieren & Steden Overlay
1. Verander niets aan je zoomniveau of resolutie!
2. Zet onder **Layers** nu **Biomes**, **Rivers**, **Routes** (wegen), **Burgs** (steden) en **Labels** aan.
3. Klik op **Export** $\rightarrow$ **PNG** en sla op als `azgaar-overlay.png`.

### C. Hoogtekaart Vloeiend Maken (ImageMagick Smoothing)
Omdat een standaard 8-bit PNG maar 256 grijstinten heeft, kunnen berghellingen in Minecraft er soms uitzien als scherpe "trappetjes" (*terracing*). Met één `ImageMagick` commando op je laptop maak je er een 16-bit PNG van met een subtiele blur, zodat alle heuvels natuurlijk glooien:

```bash
# Installeer imagemagick indien nodig (sudo apt install imagemagick of brew install imagemagick)
magick azgaar-heightmap-raw.png -depth 16 -gaussian-blur 0x3 azgaar-heightmap-smooth.png
```

---

## Stap 4: Omzetten naar Minecraft met WorldPainter

[WorldPainter](https://www.worldpainter.net/) is een gratis, open-source Java-programma waarmee je de heightmap omzet naar een echte Minecraft `26.3` / `1.21+` wereld.

### 1. Importeren van de Heightmap
1. Open WorldPainter en kies **File** $\rightarrow$ **Import New World** $\rightarrow$ **From Height Map...**
2. Selecteer `azgaar-heightmap-smooth.png`.
3. Stel de schaal en hoogtes in voor moderne Minecraft versies (`-64` tot `320`):
   * **Scale:** `100%` (1 pixel = 1 blok).
   * **Water level (Zeeniveau):** `62`.
   * **Heightmap mapping:**
     * *Low mapping (Image 0 / Zwart):* `-32` (oceaanbodem).
     * *High mapping (Image 255 of 65535 / Wit):* `240` (zodat spelers op de hoogste berg van `Y=240` nog tot `Y=320` torens kunnen bouwen).
4. Klik op **OK**. Je ziet nu jullie TTRPG-continent in 2D en 3D (`Ctrl + R` opent de 3D-weergave).

### 2. De Azgaar Overlay als Overtrekpapier Instellen
1. Ga in WorldPainter naar **View** $\rightarrow$ **Configure View...** (`Ctrl + V`).
2. Vink **Show image overlay** aan en selecteer `azgaar-overlay.png`.
3. Zet **Transparency** op `50%`.
4. Je ziet nu exact waar Azgaar de rivieren, biomen, handelsroutes en TTRPG-steden heeft getekend!

### 3. Biomen, Bossen, Rivieren en Wegen Schilderen
* **Rivieren uitgraven:** Kies de **Height tool** of een **Custom Ground Cover Layer (Water)** en trek met de kwast de rivierlijnen van de overlay over van berg naar zee.
* **Handelswegen aanleggen (Structuur voor Spelers):** Kies het terrein-type **Dirt Path** (of *Cobblestone / Coarse Dirt*) en trek de gestippelde handelsroutes uit Azgaar over. 
  * *Pedagogisch detail:* Fysieke paden tussen de Spawn Hub en de grote steden voorkomen dat jongeren verdwalen en geven direct richting ("Volg de oude handelsweg naar het noorden!").
* **Bossen & Natuur:** Gebruik de **Forest Layers** (Deciduous, Pine, Swamp) of download een gratis *Custom Tree Repository* (bijv. van Lentebriesje op PlanetMinecraft) om epische fantasy-wouden te schilderen op de groene gebieden van je overlay.

---

## Stap 5: Pedagogisch Wereld-Ontwerp ("Het Concentrische Ringen Model")

Richt de kaart in WorldPainter in volgens drie veiligheidsringen:

| Ring | Gebied op de TTRPG-Kaart | Inrichting in WorldPainter & Plugins |
| :--- | :--- | :--- |
| **Ring 1: De Veilige Vallei (Centrum)** | De hoofdstad of centrale Gilde-vestiging uit jullie TTRPG. | Vlak, overzichtelijk terrein rondom het Spawn-punt. Geen vijandige mobs (`doMobSpawning false` in WorldGuard/GriefPrevention regio), veel ruimte aan het water en langs de hoofdwegen zodat jongeren veilig hun eigen kavel kunnen claimen. |
| **Ring 2: Het Avonturen-Grensland** | De omliggende bossen, dorpen en oude handelsroutes. | Heuvelachtig terrein met paden naar TTRPG-dorpen. Hier staan `Citizens` NPC's met `BetonQuest`-verhalen en de ingangen (bijv. een stenen poort in een heuvel) waar DM's met hun `MythicDungeons` Toverstaf een 2–6 speler Puzzel-Dungeon aan koppelen. |
| **Ring 3: De Onbekende Wildernis (Buitenrand)** | Gevaarlijke bergketens, vulkanen, eilanden of diepe jungles. | Ruig terrein zonder aangelegde paden. Dit is het domein van de **Verkenners**: door hier nieuwe gebieden te voet in kaart te brengen en terug te keren naar de Hub, spelen ze stukken vrij op de gedeelde **Gilde-Atlas** en ontgrendelen ze locaties voor server-brede **Multi-Squad Raids**. |

---

## Stap 6: Exporteren naar de Pelican Server & Pre-Generatie

1. Klik in WorldPainter op **File** $\rightarrow$ **Export** $\rightarrow$ **Export as new Minecraft map...**
2. **Belangrijke Export-instellingen:**
   * **Map format:** Kies de nieuwste ondersteunde Minecraft versie (`1.20.5+ / 1.21+`).
   * **Allow Minecraft to populate the entire terrain:** Laat dit **UIT** staan als je zelf alle bomen en wegen in WorldPainter hebt geschilderd (anders zet Minecraft willekeurige standaard-bomen midden op jullie wegen). Wil je wél dat *BetterStructures* of standaard ertsen onder de grond verschijnen? Vink dan onder het tabblad **Resources** aan dat Minecraft ondergrondse ertsen (*Resources everywhere*) en grotten (*Caverns/Chasms*) genereert.
3. **Plaatsen in de Server:**
   * Kopieer de geëxporteerde `world`-map naar het Pelican server-volume op je laptop (`/var/lib/pelican/volumes/<uuid>/world`).
4. **Wereldgrens & Chunky Pre-Generatie (Voorkomt Lag):**
   * Voer eenmalig in de Pelican Console uit (voor een `4096x4096` wereld met centrum op `0,0`):
     ```text
     worldborder center 0 0
     worldborder set 4096
     ```
   * Laat eventueel **BlueMap** eenmalig renderen (`bluemap render world`) zodat jullie als admins en DM's op de beveiligde 3D-webkaart direct kunnen zien waar jullie de eerste NPC's en Dungeon-ingangen gaan plaatsen!