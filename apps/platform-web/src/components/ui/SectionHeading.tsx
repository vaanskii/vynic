type SectionHeadingProps = {
  id?: string;
  kicker?: string;
  title: string;
  body?: string;
  align?: "left" | "center";
};

export function SectionHeading({
  id,
  kicker,
  title,
  body,
  align = "left",
}: SectionHeadingProps) {
  const centered = align === "center";

  return (
    <div id={id} className={centered ? "mx-auto max-w-3xl text-center" : "max-w-3xl"}>
      {kicker ? (
        <p className="mb-4 font-vynic-mono text-xs font-semibold uppercase tracking-[0.18em] text-vynic-plum">
          {kicker}
        </p>
      ) : null}
      <h2 className="text-3xl font-semibold leading-[1.08] text-vynic-charcoal sm:text-4xl lg:text-5xl">
        {title}
      </h2>
      {body ? (
        <p
          className={`mt-5 text-base leading-7 text-vynic-muted sm:text-lg ${
            centered ? "mx-auto" : ""
          } max-w-2xl`}
        >
          {body}
        </p>
      ) : null}
    </div>
  );
}
