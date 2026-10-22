import type { ReactNode } from "react";
import { Navbar } from "../components/layout/Navbar";
import { LocaleProvider } from "../lib/i18n";
import "./customer.css";

/**
 * Owner pages outside the dashboard (sign-in, access requests, invitations) sit in
 * the Vynic site itself: same navigation, background and type. Owner flows
 * are Georgian-first and do not change the visitor's saved site language.
 */
export function PublicFrame({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <LocaleProvider locale="ka" title={`${title} | Vynic`}>
      <div className="min-h-[100dvh] bg-vynic-background text-vynic-charcoal">
        <Navbar />
        <main className="customer customer-public">{children}</main>
      </div>
    </LocaleProvider>
  );
}
