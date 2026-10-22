import { Fragment } from "react";

/**
 * Renders text as masked words for a clipped line-by-line reveal. Assistive
 * technology reads the plain string; the animated copy is hidden from it.
 * Wrapping stays natural at every width because words, not measured lines,
 * are split.
 */
export function SplitWords({ text }: { text: string }) {
  const words = text.split(/\s+/).filter(Boolean);
  return (
    <>
      <span className="sr-only">{text}</span>
      <span aria-hidden="true">
        {words.map((word, index) => (
          <Fragment key={`${word}-${index}`}>
            <span className="vynic-word-mask">
              <span className="vynic-word">{word}</span>
            </span>
            {index < words.length - 1 ? " " : null}
          </Fragment>
        ))}
      </span>
    </>
  );
}
