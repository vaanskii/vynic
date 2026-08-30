import { FormEvent, useState } from "react";
import { CheckCircle, SpinnerGap, WarningCircle } from "@phosphor-icons/react";
import { Button } from "../ui/Button";
import { SectionHeading } from "../ui/SectionHeading";
import { useLocale } from "../../lib/i18n";

type FormState = "idle" | "loading" | "success" | "error";

type LeadForm = {
  name: string;
  restaurant: string;
  phone: string;
  email: string;
  message: string;
};

const emptyForm: LeadForm = {
  name: "",
  restaurant: "",
  phone: "",
  email: "",
  message: "",
};

export function DemoForm() {
  const { copy } = useLocale();
  const [form, setForm] = useState<LeadForm>(emptyForm);
  const [state, setState] = useState<FormState>("idle");
  const [error, setError] = useState("");

  function updateField(field: keyof LeadForm, value: string) {
    setForm((current) => ({ ...current, [field]: value }));
    if (state === "error") {
      setState("idle");
      setError("");
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!form.name.trim() || !form.restaurant.trim() || !form.phone.trim()) {
      setState("error");
      setError(copy.form.requiredError);
      return;
    }

    setState("loading");
    setError("");

    window.setTimeout(() => {
      setState("success");
    }, 700);
  }

  return (
    <section id="contact" className="border-t border-vynic-border bg-vynic-surface px-4 py-20 sm:px-6 lg:px-8 lg:py-28">
      <div className="mx-auto grid max-w-7xl gap-10 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
        <div>
          <SectionHeading
            kicker={copy.form.kicker}
            title={copy.form.title}
            body={copy.form.body}
          />
          <div className="mt-8 grid gap-3">
            {copy.form.steps.map(({ number, title, body }) => (
              <div key={number} className="grid grid-cols-[36px_1fr] gap-4 border-t border-vynic-border py-4 last:border-b">
                <span className="font-vynic-mono text-[10px] font-semibold tracking-[0.14em] text-vynic-plum">{number}</span>
                <div>
                  <p className="text-sm font-semibold text-vynic-charcoal">{title}</p>
                  <p className="mt-1 text-sm leading-6 text-vynic-muted">{body}</p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <form
          className="vynic-neu-surface rounded-[8px] border border-vynic-border bg-vynic-background p-5 shadow-[0_22px_70px_color-mix(in_srgb,var(--vynic-charcoal)_8%,transparent)] sm:p-7"
          onSubmit={handleSubmit}
          noValidate
        >
          <div className="grid gap-5 sm:grid-cols-2">
            <Field
              label={copy.form.name}
              value={form.name}
              onChange={(value) => updateField("name", value)}
              required
              autoComplete="name"
            />
            <Field
              label={copy.form.restaurant}
              value={form.restaurant}
              onChange={(value) => updateField("restaurant", value)}
              required
              autoComplete="organization"
            />
            <Field
              label={copy.form.phone}
              value={form.phone}
              onChange={(value) => updateField("phone", value)}
              required
              autoComplete="tel"
              inputMode="tel"
            />
            <Field
              label={copy.form.email}
              value={form.email}
              onChange={(value) => updateField("email", value)}
              autoComplete="email"
              inputMode="email"
            />
          </div>

          <label className="mt-5 grid gap-2 text-sm font-semibold text-vynic-charcoal">
            {copy.form.message}
            <textarea
              className="vynic-neu-inset min-h-32 resize-y rounded-[8px] border border-vynic-border bg-vynic-surface px-4 py-3 text-base font-normal leading-6 text-vynic-charcoal outline-none transition placeholder:text-vynic-muted focus:border-vynic-plum focus:ring-2 focus:ring-vynic-plum/25"
              value={form.message}
              onChange={(event) => updateField("message", event.target.value)}
              placeholder={copy.form.placeholder}
            />
          </label>

          {state === "error" ? (
            <div className="mt-5 flex items-start gap-3 rounded-[8px] border border-vynic-red/35 bg-[color-mix(in_srgb,var(--vynic-red)_10%,var(--vynic-surface))] p-4 text-sm leading-6 text-vynic-charcoal">
              <WarningCircle className="mt-0.5 shrink-0 text-vynic-red" size={20} weight="duotone" />
              <span>{error}</span>
            </div>
          ) : null}

          {state === "success" ? (
            <div className="mt-5 flex items-start gap-3 rounded-[8px] border border-vynic-green/40 bg-[color-mix(in_srgb,var(--vynic-green)_13%,var(--vynic-surface))] p-4 text-sm leading-6 text-vynic-charcoal">
              <CheckCircle className="mt-0.5 shrink-0 text-vynic-green" size={20} weight="duotone" />
              <span>{copy.form.success}</span>
            </div>
          ) : null}

          <div className="mt-6 flex flex-wrap items-center gap-4">
            <Button type="submit" disabled={state === "loading"} icon={state === "loading" ? SpinnerGap : undefined}>
              {state === "loading" ? copy.form.sending : copy.nav.bookDemo}
            </Button>
            <p className="max-w-sm text-sm leading-6 text-vynic-muted">
              {copy.form.note}
            </p>
          </div>
        </form>
      </div>
    </section>
  );
}

type FieldProps = {
  label: string;
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  autoComplete?: string;
  inputMode?: "text" | "email" | "tel";
};

function Field({
  label,
  value,
  onChange,
  required = false,
  autoComplete,
  inputMode = "text",
}: FieldProps) {
  return (
    <label className="grid gap-2 text-sm font-semibold text-vynic-charcoal">
      {label}
      <input
        className="vynic-neu-inset h-12 rounded-[8px] border border-vynic-border bg-vynic-surface px-4 text-base font-normal text-vynic-charcoal outline-none transition placeholder:text-vynic-muted focus:border-vynic-plum focus:ring-2 focus:ring-vynic-plum/25"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        required={required}
        autoComplete={autoComplete}
        inputMode={inputMode}
      />
    </label>
  );
}
