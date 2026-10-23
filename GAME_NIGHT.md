# Spotify, överlämning och revansch

## Spotify

Musikkortet använder en direktlänk när en kataloglänk eller en länk vald av spelledaren finns. Annars visas **Sök låten i Spotify** med en tydlig upplysning om att versionen behöver väljas. Inget Spotify API används och ingen automatisk uppspelning sker.

Två kataloglänkar är kontrollerade mot Spotifys artist-, titel- och albumuppgifter: [Mamma Mia, ABBA, 1975](https://open.spotify.com/track/2TxCwUlqaOH3TIyJqGgR91) och [Killer Queen, Queen, 1974](https://open.spotify.com/track/1KPMTL3BRLBWrNY8fveVy6). Detta är metadataidentifiering, inte en genomlyssning eller ett löfte om tillgänglighet i varje region. Övriga 198 låtar använder fortfarande sökning tills länkar granskas. Alla låtbankens årtal är inte verifierade.

Under **Välj eller rätta Spotify-länk** kan spelledaren klistra in en spårlänk och bekräfta rätt artist/titel/inspelning. Sök-, album-, spelliste- och externa länkar avvisas. Delningsparametrar och språkprefix normaliseras. Länken sparas i rummet, utan att skriva över den gemensamma katalogen.

**Rapportera fel låt eller årtal** finns privat på musikkortet och för deltagare efter rättningen. Beskrivning och ett valfritt länkförslag sparas för manuell granskning av projektägaren i Supabase-tabellen `song_reports`. Ingen e-post eller extern avisering skickas. Rapporter ändrar inte automatiskt årtal eller poäng. Högst 20 rapporter per identitet och dygn. Reporteridentiteten blir null när ett gammalt anonymt konto städas bort; rapporten behålls tills ägaren hanterat den.

## Spelledare och reserv

På mobilen finns **Spelledare och reserv**. Nuvarande spelledare kan utse en ansluten deltagare till reserv eller lämna över direkt. Spelarnas poäng, kort, låsta svar och pågående runda behålls.

En utsedd reserv får knappen **Ta över som reserv** efter två minuter utan livstecken från spelledaren. Ingen godtycklig deltagare kan ta över. Om ingen reserv utsetts måste den ursprungliga spelledaren återansluta med sin identitet eller privata återanslutningskod. Ett tillfälligt nätavbrott avslutar inte rummet.

Överlämning och återtagning av personens plats är separata saker: en tidigare spelledare får inte tillbaka rollen genom sin gamla återanslutningskod efter att rollen överlämnats. Reservkopplingen följer medlemskapet även vid återanslutning till en ny identitet.

## Revansch

När spelet är färdigt kan spelledaren välja **Revansch med samma gäng**. Samma rum, TV-länk, deltagaridentiteter och återanslutningskoder används. Poäng och tidslinjer nollställs, medan spelläge och poängmål behålls. Ni återkommer till lobbyn och kan justera målet före nästa start.

Kort som redan delats ut eller spelats i rummet väljs inte igen. Historiken delas över alla revanscher i samma rum. Om för få ospelade låtar återstår visas ett fel som ber er skapa ett nytt rum; appen återanvänder inte låtar i smyg. Ett nytt rum får en ny kortlek och kräver ny anslutning.

## Installation och verifiering

`supabase/game_night.sql` körs efter tidigare databasuppdateringar. Tabellerna för rapporter, länkar, historik och reserver är RLS-skyddade och saknar direkt klientåtkomst; behörighetskontrollerade RPC:er används.

Nio Node-tester, produktionsbygge och `tests/game-night.sql` kontrollerar länknormalisering, rapport-/länkbehörighet, dolt låtkort, reservens tidsgräns, överlämning och revansch med bevarad deltagarlista och regler utan återanvända låtar. Övriga SQL-regressionstester körs också. Faktisk lyssning i Spotify och fysisk TV ingår inte i dessa tester.

Verifierat även mot riktig Supabase med två separata testidentiteter: reservval, direkt överlämning, rumsspecifik länk, spel till seger, revansch med samma deltagare/regler och inga återanvända låtar. Gränssnittet visar de nya reserv-, länk- och rapportkontrollerna utan att avslöja årtalet på musikkortet.
