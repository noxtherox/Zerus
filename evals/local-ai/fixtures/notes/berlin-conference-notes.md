---
title: DevDays Berlin — conference notes
tags: [conference, berlin, engineering]
people: [Sabine Krüger, Oskar Lindqvist]
---
# DevDays Berlin 2026 — notes

Dates: 8–9 June 2026 · Venue: Spreehalle Kreuzberg

## Keynote — Oskar Lindqvist: "Offline-first is a product decision"
- Sync conflicts are a UX problem before they are a database problem
- His team cut support tickets by 31% after showing conflict previews
- Recommends CRDTs only for collaborative text, not for settings

## Talk — Sabine Krüger: „Kleine Modelle, große Wirkung“ (in German)
- Lokale Modelle unter 2 Milliarden Parametern reichen für Klassifikation und kurze Zusammenfassungen.
- Ihr Team nutzt ein 1,5B-Modell zur Ticket-Klassifizierung mit 92 % Genauigkeit.
- Wichtig: Evaluierungsdaten in allen Sprachen der Nutzer, nicht nur auf Englisch.
- Die Quantisierung auf 4 Bit hat kaum Qualität gekostet (minus 1,5 Prozentpunkte).

## My takeaways
- Try conflict previews in our sync UI
- Build a multilingual eval set before choosing a model
- Ask Sabine for her slides
