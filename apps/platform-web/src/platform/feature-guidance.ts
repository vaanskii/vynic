export const featureDescriptions: Record<string, string> = {
  POS: "მაგიდები, შეკვეთები, გადახდა და გაყიდვები POS-ში.",
  INVENTORY: "მიღებები, ნაშთები და შემადგენლობები მენეჯერში; POS-ში — დათვალიერება.",
  MANAGER_APP: "მენეჯერის აპში შესვლა და რესტორნის დისტანციური მართვა.",
  MANAGER_RESERVATIONS: "რეზერვაციების მართვა მენეჯერის აპში. POS-ის ადგილობრივი რეზერვაციები ცალკე რჩება.",
  PAYROLL: "თანამშრომლების ანაზღაურება, დარიცხვები და გადახდები მენეჯერში.",
  FINANCIAL_PLANNING: "პერიოდული ვალდებულებები და თანხის რეზერვის დაგეგმვა მენეჯერში.",
  ADVANCED_AUDIT: "დამატებითი აქტივობის ისტორია. ძირითადი შეკვეთის აუდიტი ყოველთვის შენარჩუნდება.",
  NON_FISCAL_CLOSE: "არაფისკალური დახურვა და მისი გაყიდვების ბლოკები. გამორთვა ისტორიულ ჩანაწერებს არ შლის.",
  PROFITABILITY: "მიმდინარე თვითღირებულება და მარაგის შეფასება. გაყიდვების ისტორიულ თვითღირებულებასა და სრულ მოგების ანგარიშს ჯერ არ მოიცავს.",
  WEBSITE: "არსებული რესტორნის ვებგვერდის სერვისებზე წვდომა. მზა საიტს ავტომატურად არ ქმნის; საჭიროა ცალკე საიტისა და დომენის გამართვა.",
};
export function featureWarnings(keys: Iterable<string>): string[] {
  const enabled = new Set(keys);
  const warnings: string[] = [];
  if (!enabled.has("MANAGER_APP")) {
    const managerOnly = [["PAYROLL", "ხელფასები"], ["FINANCIAL_PLANNING", "ფინანსური დაგეგმვა"], ["MANAGER_RESERVATIONS", "რეზერვაციების მართვა"]].filter(([key]) => enabled.has(key)).map(([, name]) => name);
    if (managerOnly.length) warnings.push(`${managerOnly.join(", ")} მენეჯერის აპში გამოსაყენებლად ჩართეთ „მენეჯერის აპლიკაცია“.`);
    if (enabled.has("INVENTORY")) warnings.push("მარაგების შესაცვლელად ჩართეთ „მენეჯერის აპლიკაცია“. POS-ში მხოლოდ დათვალიერება იქნება ხელმისაწვდომი.");
    if (enabled.has("ADVANCED_AUDIT")) warnings.push("აქტივობის ისტორიის მენეჯერში სანახავად ჩართეთ „მენეჯერის აპლიკაცია“. POS-ის წვდომა ცალკე რჩება.");
  }
  if (enabled.has("PROFITABILITY") && !enabled.has("INVENTORY")) warnings.push("მიმდინარე თვითღირებულებისა და მარაგის შეფასების სანახავად ჩართეთ „მარაგები“.");
  if (enabled.has("NON_FISCAL_CLOSE") && !enabled.has("POS")) warnings.push("არაფისკალური დახურვა POS-ის ფუნქციაა; გადაამოწმეთ „გაყიდვების სისტემის“ წვდომა.");
  return warnings;
}
