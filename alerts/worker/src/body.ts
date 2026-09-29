// CAP <description> -> the `body` and `translations_url` the app renders.
//
// Every rule here is from the five archived descriptions (ALERTS_SERVICE.md,
// "Body"). Anything that does not match is left in place: a boilerplate line
// shown twice is harmless, a sentence silently deleted is not.

export interface Body {
  body: string;
  translations_url: string | null;
}

// "Notification issued 09-29-2026 at 05:17 AM." - 5 of 5. Duplicates `sent`.
const ISSUED = /^Notification issued \d{2}-\d{2}-\d{4} at \d{1,2}:\d{2} [AP]M\.?[ \t]*\n+/i;

// "To view this message in American Sign Language (ASL), العربية, … : http://on.nyc.gov/1kdbhe2."
// 4 of 5, always last. The URL ends at whitespace; a trailing full stop is
// the sentence's, not the URL's.
const TRANSLATIONS = /\n*To view this message in[^\n]*?:\s*(https?:\/\/\S+?)\.?\s*$/;

export function cleanBody(description: string): Body {
  let text = description
    .replace(/\r\n?/g, "\n")
    .replace(/ /g, " ");

  text = text.replace(ISSUED, "");

  let translations_url: string | null = null;
  const footer = TRANSLATIONS.exec(text);
  if (footer) {
    translations_url = footer[1];
    text = text.slice(0, footer.index);
  }

  text = text
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/, ""))
    .join("\n")
    // Keep single newlines - NWS relays put What:/Where:/When: and "- "
    // bullets on their own lines - but no more than one blank line in a row.
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  return { body: text, translations_url };
}
