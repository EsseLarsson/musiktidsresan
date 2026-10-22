# Uppdatering efter familjetestet

- TV: kompakt layout, standardstorlek 85 %, storleksval 50–100 % och helskärmsknapp om webbläsaren stöder det. Högst fyra spelare visas åt gången, med automatisk växling var 15:e sekund och manuell Nästa-knapp. De fem sista korten i varje tidslinje visas på TV; spelarens egen mobil har hela tidslinjen.
- Återanslutning: en omladdning återställer nu även spelarvyn automatiskt. Startsidan har Fortsätt i rum och ett formulär för återanslutning med privat kod. Poäng, tidslinje, låst svar och eventuell spelledarroll bevaras.
- Privat kod: fås genom Spara min återanslutningskod inne i rummet. Kopiera den före byte av enhet eller rensning av webbläsardata. Koden är personlig och får inte delas. Den sparas lokalt för automatisk återanslutning och byts vid byte av inloggad identitet. Den ligger aldrig i QR-koden eller inbjudningslänken.
- Maxpoäng: tydligt heltalsfält 1–20 före rumsskapande och före demostart. Spelledaren kan även ändra och spara maxpoängen i lobbyn. När spelet startat är målet låst. Alla deltagare ser det sparade målet.

Databasändringen finns i `supabase/session_recovery.sql` och är installerad i det anslutna Supabase-projektet. Gamla rum utan sparad återanslutningskod kan bara återtas om den ursprungliga webbläsaridentiteten finns kvar. Avslutade eller utgångna rum och borttagna spelare går inte att återställa med koden. Rumskod och ett kopierat spelarnamn ger inte åtkomst till någon annans poäng eller spelledarroll.

## Verifierat

- Åtta Node-tester och produktionsbygge.
- PostgreSQL-testet `tests/recovery.sql`: spara eget poängmål, rättigheter, gränser, ändringsstopp efter start, fel kod, privat återställning till ny identitet, bevarad poäng och låst svar, återställning av spelledarroll, kodrotation samt spärrade spelare/avslutade rum.
- Webbläsare mot ansluten Supabase: skapat rum med sju poäng, ändrat till nio i lobbyn och laddat om. Spelledarroll och mål återställdes automatiskt.
- TV-layout med fyra spelare och tio kort var verifierad lokalt vid 1280 × 720. Sidans höjd och bredd höll sig inom bildytan utan rullning vid 85 %. `?layouttest=1` är enbart en lokal utvecklingsfixture och ingår inte i produktionsappen.
- Verklig Hitachi-TV och dess helskärmsstöd har inte testats. Storleksreglaget kan kompensera för webbläsarens egna verktygsfält.

Ett försök att lägga till syntetiska spelare i ett anslutet testrum nekades av automatisk säkerhetsgranskning. Inga extra spelare lades till där; fyrspelartestet gjordes i en fristående lokal fixture.
