import { createContext, useContext, useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import type { ReactNode } from 'react';

export type Language = 'en' | 'ka' | 'ru';

/** Supported language codes — order defines the switcher cycle */
export const LANGUAGES: Language[] = ['en', 'ka', 'ru'];

interface LanguageContextType {
  language: Language;
  setLanguage: (lang: Language) => void;
  t: (key: string) => string;
}

const LanguageContext = createContext<LanguageContextType | undefined>(undefined);

interface Translations {
  [key: string]: {
    en: string;
    ka: string;
    /** Optional — falls back to English when missing */
    ru?: string;
  };
}

const translations: Translations = {
  // Navigation
  'nav.home': { en: 'Home', ka: 'მთავარი', ru: 'Главная' },
  'nav.about': { en: 'About', ka: 'ჩვენ შესახებ', ru: 'О нас' },
  'nav.menu': { en: 'Menu', ka: 'მენიუ', ru: 'Меню' },
  'nav.atmosphere': { en: 'Atmosphere', ka: 'გარემო', ru: 'Атмосфера' },
  'nav.reservations': { en: 'Reservations', ka: 'დაჯავშნა', ru: 'Бронирование' },
  'nav.contact': { en: 'Contact', ka: 'კონტაქტი', ru: 'Контакты' },
  'nav.profile': { en: 'Profile', ka: 'პროფილი', ru: 'Профиль' },

  // Header
  'header.title': { en: 'VANKISI', ka: 'ვანკისი', ru: 'ВАНКИСИ' },
  'header.tagline': { en: 'Place where tradition meets taste', ka: 'ადგილი, სადაც ტრადიცია ხვდება გემოს', ru: 'Место, где традиции встречаются со вкусом' },
  'header.description': {
    en: "We're thrilled to bring authentic Georgian flavors to your neighborhood! From our freshly baked khachapuri to traditional mtsvadi, every dish is prepared with recipes passed down through generations. Come celebrate our grand opening with us!",
    ka: 'ჩვენ ხალისით ვაწვდით ავთენტურ ქართულ გემოებს თქვენს უბანში! ჩვენი ახლად გამომცხვარი ხაჭაპურიდან ტრადიციულ მწვადამდე, ყოველი კერძი მზადდება რეცეპტებით, რომლებიც თაობიდან თაობაში გადაეცა. მოდით, იზეიმეთ ჩვენთან ერთად!',
    ru: 'Мы рады привнести аутентичные грузинские вкусы в ваш район! От свежеиспечённого хачапури до традиционного мцвади — каждое блюдо готовится по рецептам, передаваемым из поколения в поколение. Приходите отпраздновать наше открытие вместе с нами!'
  },
  'header.bookTable': { en: 'Book Your Table', ka: 'მაგიდის დაჯავშნა', ru: 'Забронировать столик' },
  'header.exploreMenu': { en: 'Explore Menu', ka: 'მენიუს დათვალიერება', ru: 'Открыть меню' },
  'header.grandOpening': { en: 'Grand Opening Special', ka: 'გრანდ ოფენინგ სპეციალი', ru: 'Специальное открытие' },
  'header.authenticRecipes': { en: 'Authentic Georgian Recipes', ka: 'ავთენტური ქართული რეცეპტები', ru: 'Аутентичные грузинские рецепты' },
  'header.grandOpeningCard': { en: 'Grand Opening!', ka: 'გრანდ ოფენინგი!', ru: 'Грандиозное открытие!' },
  'header.grandOpeningDesc': {
    en: "We're excited to serve you authentic Georgian cuisine! Visit us this week and enjoy 15% off your first meal as we celebrate our grand opening.",
    ka: 'ჩვენ აღფრთოვანებული ვართ ავთენტური ქართული სამზარეულოთი მოგემსახუროთ! ეწვიეთ ამ კვირაში და ისარგებლეთ 15% ფასდაკლებით პირველ ჭამაზე!',
    ru: 'Мы рады угостить вас аутентичной грузинской кухней! Посетите нас на этой неделе и получите скидку 15% на первый заказ в честь нашего открытия.'
  },

  // Contact
  'contact.title': { en: 'Contact Us', ka: 'დაგვიკავშირდით' },
  'contact.getInTouch': { en: 'Get in Touch', ka: 'დაგვიკავშირდით', ru: 'Связаться с нами' },
  'contact.address': { en: 'Address', ka: 'მისამართი', ru: 'Адрес' },
  'contact.phone': { en: 'Phone', ka: 'ტელეფონი' },
  'contact.email': { en: 'Email', ka: 'ელ. ფოსტა' },
  'contact.hours': { en: 'Hours', ka: 'სამუშაო საათები' },
  'contact.followUs': { en: 'Follow Us', ka: 'გამოგვყევით', ru: 'Мы в соцсетях' },
  'contact.findUs': { en: 'Find Us', ka: 'იპოვეთ ჩვენ' },
  'contact.getDirections': { en: 'Get Directions', ka: 'მისვლის გზა' },
  'contact.parking': { en: 'Parking & Transportation', ka: 'პარკირება და ტრანსპორტი' },
  'contact.stayUpdated': { en: 'Stay Updated', ka: 'იყავით განახლებული' },
  'contact.newsletter': {
    en: 'Subscribe to our newsletter for special events, seasonal menus, and exclusive offers.',
    ka: 'გამოიწერეთ ჩვენი სიახლეები სპეციალური ღონისძიებების, სეზონური მენიუებისა და ექსკლუზიური შეთავაზებებისთვის.'
  },
  'contact.subscribe': { en: 'Subscribe', ka: 'გამოწერა' },
  'contact.copyright': { en: '© 2025 Vankisi Restaurant. All rights reserved.', ka: '© 2025 ვანკისი რესტორანი. ყველა უფლება დაცულია.', ru: '© 2025 Ресторан Vankisi. Все права защищены.' },
  'contact.privacyPolicy': { en: 'Privacy Policy', ka: 'კონფიდენციალურობის პოლიტიკა', ru: 'Политика конфиденциальности' },
  'contact.termsOfService': { en: 'Terms of Service', ka: 'მომსახურების პირობები', ru: 'Условия использования' },
  'contact.accessibility': { en: 'Accessibility', ka: 'ხელმისაწვდომობა', ru: 'Доступность' },
  'contact.address.value': { en: 'Georgia - Batumi\nPushkini ST N51', ka: 'საქართველო - ბათუმი\nპუშკინის ქ. N51', ru: 'Грузия — Батуми\nул. Пушкина N51' },
  'contact.phone.availability': { en: 'Available during business hours', ka: 'ხელმისაწვდომია სამუშაო საათებში' },
  'contact.email.response': { en: 'We respond within 24 hours', ka: 'ჩვენ გიპასუხებთ 24 საათის განმავლობაში' },
  'contact.map.loading': { en: 'Loading Map...', ka: 'რუკა იტვირთება...' },
  'contact.map.location': { en: 'Vankisi Restaurant Location', ka: 'ვანკისი რესტორნის მდებარეობა' },
  'contact.email.placeholder': { en: 'Enter your email', ka: 'შეიყვანეთ თქვენი ელ. ფოსტა' },

  // Page Titles
  'title.home': { en: 'Vankisi · Restaurant', ka: 'ვანკისი · რესტორანი' },
  'title.about': { en: 'Vankisi · About', ka: 'ვანკისი · ჩვენ შესახებ' },
  'title.menu': { en: 'Vankisi · Menu', ka: 'ვანკისი · მენიუ' },
  'title.reservations': { en: 'Vankisi · Reservations', ka: 'ვანკისი · დაჯავშნა' },
  'title.contact': { en: 'Vankisi · Contact', ka: 'ვანკისი · კონტაქტი' },
  'title.login': { en: 'Vankisi · Login', ka: 'ვანკისი · შესვლა' },
  'title.register': { en: 'Vankisi · Signup', ka: 'ვანკისი · რეგისტრაცია' },
  'title.selecttable': { en: 'Vankisi · Select Table', ka: 'ვანკისი · მაგიდის არჩევა' },

  // Authentication
  'auth.login': { en: 'Login', ka: 'შესვლა' },
  'auth.register': { en: 'Register', ka: 'რეგისტრაცია' },
  'auth.email': { en: 'Email', ka: 'ელ. ფოსტა' },
  'auth.password': { en: 'Password', ka: 'პაროლი' },
  'auth.firstName': { en: 'First Name', ka: 'სახელი' },
  'auth.lastName': { en: 'Last Name', ka: 'გვარი' },
  'auth.phone': { en: 'Phone Number', ka: 'ტელეფონის ნომერი' },
  'auth.confirmPassword': { en: 'Confirm Password', ka: 'პაროლის დადასტურება' },
  'auth.loginDescription': { en: 'Welcome back! Sign in to your account', ka: 'კეთილი იყოს თქვენი დაბრუნება! შედით თქვენს ანგარიშში' },
  'auth.registerDescription': { en: 'Create a new account to get started', ka: 'შექმენით ახალი ანგარიში დასაწყებად' },
  'auth.emailPlaceholder': { en: 'your@email.com', ka: 'თქვენი@ელფოსტა.გე' },
  'auth.passwordPlaceholder': { en: 'Enter your password', ka: 'შეიყვანეთ პაროლი' },
  'auth.firstNamePlaceholder': { en: 'Enter your first name', ka: 'შეიყვანეთ სახელი' },
  'auth.lastNamePlaceholder': { en: 'Enter your last name', ka: 'შეიყვანეთ გვარი' },
  'auth.phonePlaceholder': { en: '+995 XXX XXX XXX', ka: '+995 XXX XXX XXX' },
  'auth.confirmPasswordPlaceholder': { en: 'Confirm your password', ka: 'დაადასტურეთ პაროლი' },
  'auth.loggingIn': { en: 'Logging in...', ka: 'შესვლა...' },
  'auth.registering': { en: 'Registering...', ka: 'რეგისტრაცია...' },
  'auth.noAccount': { en: "Don't have an account?", ka: 'არ გაქვთ ანგარიში?' },
  'auth.haveAccount': { en: 'Already have an account?', ka: 'უკვე გაქვთ ანგარიში?' },
  'auth.backToHome': { en: 'Back to Home', ka: 'უკან მთავარზე' },
  'auth.logout': { en: 'Logout', ka: 'გასვლა' },

  // Profile
  'profile.title': { en: 'My Account', ka: 'ჩემი ანგარიში', ru: 'Мой аккаунт' },
  'profile.greeting': { en: 'Hello', ka: 'გამარჯობა', ru: 'Привет' },
  'profile.tierVip': { en: 'VIP Guest', ka: 'VIP სტუმარი', ru: 'VIP гость' },
  'profile.tierGuest': { en: 'Guest', ka: 'სტუმარი', ru: 'Гость' },
  'profile.tabRes': { en: 'My Reservations', ka: 'ჩემი ჯავშნები', ru: 'Мои бронирования' },
  'profile.tabSettings': { en: 'Settings', ka: 'პარამეტრები', ru: 'Настройки' },
  'profile.tabLogout': { en: 'Sign Out', ka: 'ანგარიშიდან გასვლა', ru: 'Выйти' },
  'profile.upcoming': { en: 'Upcoming Reservations', ka: 'მომავალი ჯავშნები', ru: 'Предстоящие бронирования' },
  'profile.past': { en: 'Visit History', ka: 'ვიზიტების ისტორია', ru: 'История визитов' },
  'profile.noUpcoming': { en: 'No upcoming reservations', ka: 'მომავალი ჯავშნები არ არის', ru: 'Нет предстоящих бронирований' },
  'profile.resDate': { en: 'Date', ka: 'თარიღი', ru: 'Дата' },
  'profile.resTime': { en: 'Time', ka: 'დრო', ru: 'Время' },
  'profile.resGuests': { en: 'Guests', ka: 'სტუმარი', ru: 'Гости' },
  'profile.resTable': { en: 'Table', ka: 'მაგიდა', ru: 'Стол' },
  'profile.preOrder': { en: 'Pre-order', ka: 'პრე-მენიუ', ru: 'Предзаказ' },
  'profile.dishes': { en: 'dishes', ka: 'კერძი', ru: 'блюд' },
  'profile.cancelBtn': { en: 'Cancel Reservation', ka: 'ჯავშნის გაუქმება', ru: 'Отменить бронирование' },
  'profile.saveBtn': { en: 'Save Changes', ka: 'ცვლილებების შენახვა', ru: 'Сохранить изменения' },
  'profile.personalInfo': { en: 'Personal Information', ka: 'პირადი ინფორმაცია', ru: 'Личная информация' },
  'profile.emailChangeNote': {
    en: 'Contact us to change your email address.',
    ka: 'ელ-ფოსტის შესაცვლელად დაუკავშირდით ადმინისტრაციას.',
    ru: 'Для смены email свяжитесь с администрацией.',
  },
  'profile.profileUpdated': { en: 'Profile updated', ka: 'პროფილი განახლდა', ru: 'Профиль обновлён' },
  'profile.email': { en: 'Email', ka: 'ელ. ფოსტა', ru: 'Эл. почта' },
  'profile.settings': { en: 'Security Settings', ka: 'უსაფრთხოების პარამეტრები', ru: 'Настройки безопасности' },
  'profile.changePassword': { en: 'Change Password', ka: 'პაროლის შეცვლა', ru: 'Сменить пароль' },
  'profile.currentPassword': { en: 'Current Password', ka: 'მიმდინარე პაროლი', ru: 'Текущий пароль' },
  'profile.newPassword': { en: 'New Password', ka: 'ახალი პაროლი', ru: 'Новый пароль' },
  'profile.confirmNewPassword': { en: 'Confirm New Password', ka: 'დაადასტურეთ ახალი პაროლი', ru: 'Подтвердите новый пароль' },
  'profile.cancel': { en: 'Cancel', ka: 'გაუქმება', ru: 'Отмена' },
  'profile.updatePassword': { en: 'Update Password', ka: 'პაროლის განახლება', ru: 'Обновить пароль' },
  'profile.passwordUpdated': { en: 'Password updated successfully', ka: 'პაროლი წარმატებით განახლდა', ru: 'Пароль успешно обновлён' },
  'profile.passwordMismatch': { en: 'Passwords do not match', ka: 'პაროლები არ ემთხვევა', ru: 'Пароли не совпадают' },
  'profile.memberSince': { en: 'Member since', ka: 'წევრი', ru: 'Участник с' },
  'profile.myReservations': { en: 'My Reservations', ka: 'ჩემი დაჯავშნები', ru: 'Мои бронирования' },
  'profile.noReservations': { en: 'No reservations found', ka: 'ჯავშნები ვერ მოიძებნა', ru: 'Бронирования не найдены' },
  'profile.reservationDetails': { en: 'Details', ka: 'დეტალები', ru: 'Детали' },
  'profile.date': { en: 'Date', ka: 'თარიღი', ru: 'Дата' },
  'profile.time': { en: 'Time', ka: 'დრო', ru: 'Время' },
  'profile.tables': { en: 'Tables', ka: 'მაგიდები', ru: 'Столы' },
  'profile.totalAmount': { en: 'Total Amount', ka: 'სულ თანხა', ru: 'Итого' },
  'profile.status': { en: 'Status', ka: 'სტატუსი', ru: 'Статус' },
  'profile.menuItems': { en: 'Pre-ordered Items', ka: 'წინასწარ შეკვეთილი კერძები', ru: 'Предзаказанные блюда' },
  'profile.notes': { en: 'Notes', ka: 'შენიშვნები', ru: 'Заметки' },
  'profile.confirmed': { en: 'Confirmed', ka: 'დადასტურებული', ru: 'Подтверждено' },
  'profile.completed': { en: 'Completed', ka: 'დასრულებული', ru: 'Завершено' },
  'profile.loading': { en: 'Loading...', ka: 'იტვირთება...', ru: 'Загрузка...' },
  'profile.error': { en: 'Error loading profile data', ka: 'პროფილის მონაცემების ჩატვირთვისას მოხდა შეცდომა', ru: 'Ошибка загрузки профиля' },

  // selectTable
  'selectTable.title': { en: 'Click Available Tables to Select', ka: 'დააწკაპეთ თავისუფალ მაგიდებს ასარჩევად' },
  'selectTable.selectDateTime': { en: 'Please select date and time first', ka: 'აირჩიეთ თარიღი და დრო' },
  'selectTable.available': { en: 'Available', ka: 'თავისუფალი' },
  'selectTable.selected': { en: 'Selected', ka: 'არჩეული' },
  'selectTable.booked': { en: 'Booked', ka: 'დაჯავშნილია' },

  // Payment Success
  'payment.success.title': { en: 'Payment Successful!', ka: 'გადახდა წარმატებულია!' },
  'payment.success.message': {
    en: 'Your reservation and payment have been completed successfully. You will receive a confirmation email shortly.',
    ka: 'თქვენი ჯავშანი და გადახდა წარმატებით დასრულდა. მალე მიიღებთ დასტურს ელ. ფოსტაზე.'
  },
  'payment.success.details': { en: 'Payment Details', ka: 'გადახდის დეტალები' },
  'payment.success.id': { en: 'Payment ID:', ka: 'გადახდის ID:' },
  'payment.success.refresh': { en: 'Refresh Status', ka: 'სტატუსის განახლება' },
  'payment.success.nextSteps': { en: "What's Next?", ka: 'შემდეგი ნაბიჯები' },
  'payment.success.step1': { en: 'A confirmation email will be sent within 5-10 minutes', ka: 'დასტურის ელ. ფოსტა გამოიგზავნება 5-10 წუთში' },
  'payment.success.step2': { en: 'We will call you 24 hours before your reservation to confirm', ka: 'ჯავშნის თარიღამდე 24 საათით ადრე დაგირეკავთ დასადასტურებლად' },
  'payment.success.step3': { en: 'Bring your confirmation or mobile phone to the restaurant', ka: 'მოიტანეთ დასტური ან მობილური ტელეფონი რესტორანში' },
  'payment.success.returnHome': { en: 'Return to Home', ka: 'მთავარ გვერდზე დაბრუნება' },
  'payment.success.contact': { en: 'If you have any questions, contact us: ', ka: 'კითხვების შემთხვევაში დაგვიკავშირდით: ' },
  'payment.loading': { en: 'Loading...', ka: 'იტვირთება...' },

  // Payment Fail
  'payment.fail.title': { en: 'Payment Failed', ka: 'გადახდა ვერ შესრულდა' },
  'payment.fail.message': { en: 'Your payment could not be completed. Please try again.', ka: 'თქვენი გადახდა ვერ დასრულდა. გთხოვთ სცადოთ ხელახლა.' },
  'payment.fail.details': { en: 'Error Details', ka: 'შეცდომის დეტალები' },
  'payment.fail.commonIssues': { en: 'Common Issues', ka: 'ხშირი პრობლემები' },
  'payment.fail.issue1': { en: 'Insufficient funds on your card', ka: 'არასაკმარისი ბალანსი ბარათზე' },
  'payment.fail.issue2': { en: 'Card has expired', ka: 'ბარათის ვადა გასულია' },
  'payment.fail.issue3': { en: 'Incorrect CVV code', ka: 'არასწორი CVV კოდი' },
  'payment.fail.issue4': { en: 'Internet connection issues', ka: 'ინტერნეტ კავშირის პრობლემა' },
  'payment.fail.issue5': { en: 'Transaction declined by bank', ka: 'ბანკის მხრიდან უარყოფა' },
  'payment.fail.whatToDo': { en: 'What Should I Do?', ka: 'რა უნდა გავაკეთო?' },
  'payment.fail.step1': { en: 'Check your card details and balance', ka: 'შეამოწმეთ ბარათის დეტალები და ბალანსი' },
  'payment.fail.step2': { en: 'Try with a different card or payment method', ka: 'სცადეთ სხვა ბარათით ან გადახდის მეთოდით' },
  'payment.fail.step3': { en: 'Contact us if the problem persists', ka: 'თუ პრობლემა გრძელდება, დაგვიკავშირდით' },
  'payment.fail.tryAgain': { en: 'Try Again', ka: 'ხელახლა ცდა' },
  'payment.fail.contact': { en: 'Need help? Contact us:', ka: 'დახმარების საჭიროებისას დაგვიკავშირდით:' },
  'payment.fail.note': { en: 'Note:', ka: 'ყურადღება:' },
  'payment.fail.noteMessage': {
    en: 'Your reservation information is saved in the cart. You can retry the payment.',
    ka: 'თქვენი ჯავშნის ინფორმაცია შენარჩუნებულია კალათაში. შეგიძლიათ ხელახლა სცადოთ გადახდა.'
  },

  // About Page
  'about.hero.title': { en: 'Our Journey', ka: 'ჩვენი მოგზაურობა' },
  'about.hero.subtitle': {
    en: 'From a humble family kitchen to a culinary destination',
    ka: 'მოკრძალებული ოჯახური სამზარეულოდან კულინარიულ დანიშნულებამდე'
  },

  'about.story.title': { en: 'The Vankisi Story', ka: 'ვანკისის ისტორია' },
  'about.story.p1': {
    en: 'It wasn\'t just about opening a restaurant. It was about sharing a piece of our soul. The Vanadze family started with a simple dream: to bring the authentic warmth of a Georgian supra to our community.',
    ka: 'ეს არ იყო მხოლოდ რესტორნის გახსნა. ეს იყო ჩვენი სულის ნაწილის გაზიარება. ვანაძეების ოჯახმა დაიწყო მარტივი ოცნებით: მოგვეტანა ქართული სუფრის ავთენტური სითბო ჩვენს თემში.'
  },
  'about.story.p2': {
    en: 'Every recipe tells a story of our travels, our ancestors, and the late nights spent perfecting the dough for our khachapuri. We invite you to be part of our ongoing adventure.',
    ka: 'თითოეული რეცეპტი ყვება ჩვენი მოგზაურობის, წინაპრების და ხაჭაპურის ცომის დახვეწაში გატარებული გვიანი ღამეების ამბავს. გეპატიჟებით გახდეთ ჩვენი მიმდინარე თავგადასავლის ნაწილი.'
  },

  'about.adventure.title': { en: 'Our Adventures', ka: 'ჩვენი თავგადასავლები' },
  'about.adventure.1.title': { en: 'Roots in Batumi', ka: 'ფესვები ბათუმში' },
  'about.adventure.1.desc': {
    en: 'Where the sea meets the mountains, our passion for fresh ingredients was born.',
    ka: 'სადაც ზღვა მთებს ხვდება, იქ დაიბადა ჩვენი ვნება ახალი ინგრედიენტების მიმართ.'
  },
  'about.adventure.2.title': { en: 'The Culinary Quest', ka: 'კულინარიული ძიება' },
  'about.adventure.2.desc': {
    en: 'Traveling across Georgia to rediscover forgotten recipes and techniques.',
    ka: 'მოგზაურობა მთელ საქართველოში დავიწყებული რეცეპტებისა და ტექნიკის აღმოსაჩენად.'
  },
  'about.adventure.3.title': { en: 'Building the Dream', ka: 'ოცნების აშენება' },
  'about.adventure.3.desc': {
    en: 'Creating a space that feels like home, brick by brick, flavor by flavor.',
    ka: 'სივრცის შექმნა, რომელიც სახლს ჰგავს, აგურით აგურზე, გემოთი გემოზე.'
  },
  'about.story.quote': { en: 'Food is the most primitive form of comfort.', ka: 'კულინარია მეტი მარტივი გამოცხადია.' },

  // Atmosphere
  'atmosphere.subtitle': { en: 'Our Ambiance', ka: 'ჩვენი გარემო' },
  'atmosphere.title': { en: 'The Atmosphere', ka: 'განსაკუთრებული გარემო' },
  'atmosphere.intro': {
    en: 'Step into a space where modern elegance meets traditional Georgian warmth. Every corner is designed to create an unforgettable dining experience.',
    ka: 'შედით სივრცეში, სადაც თანამედროვე ელეგანტურობა ხვდება ტრადიციულ ქართულ სითბოს. თითოეული კუთხე შექმნილია დაუვიწყარი გამოცდილებისთვის.'
  },
  'atmosphere.sec1Title': { en: 'Main Dining Room', ka: 'მთავარი დარბაზი' },
  'atmosphere.sec1Desc': {
    en: 'Our spacious main dining area features elegant lighting, comfortable seating, and a vibrant atmosphere perfect for both intimate dinners and lively gatherings.',
    ka: 'ჩვენი ვრცელი მთავარი დარბაზი გამოირჩევა ელეგანტური განათებით, მყუდრო ადგილებით და ცოცხალი გარემოთი, რაც იდეალურია როგორც რომანტიკული ვახშმისთვის, ისე სადღესასწაულო შეკრებებისთვის.'
  },
  'atmosphere.sec2Title': { en: 'VIP Space', ka: 'ვიპ სივრცე' },
  'atmosphere.sec2Desc': {
    en: 'For those seeking a more private and exclusive dining experience, our VIP space offers personalized service in a secluded, luxurious setting.',
    ka: 'მათთვის, ვინც ეძებს უფრო პირად და ექსკლუზიურ გამოცდილებას, ჩვენი ვიპ სივრცე გთავაზობთ პერსონალიზებულ მომსახურებას იზოლირებულ და მდიდრულ გარემოში.'
  },
  'atmosphere.sec3Title': { en: 'Lounge & Bar', ka: 'ლაუნჯი და ბარი' },
  'atmosphere.sec3Desc': {
    en: 'Relax and unwind at our stylish lounge. Enjoy masterfully crafted cocktails and premium Georgian wines in a chic, laid-back environment.',
    ka: 'დაისვენეთ ჩვენს დახვეწილ ლაუნჯში. ისიამოვნეთ ოსტატურად მომზადებული კოქტეილებითა და პრემიუმ ქართული ღვინოებით გემოვნებიან, მშვიდ გარემოში.'
  },
  'atmosphere.gallery': { en: 'Gallery', ka: 'გალერეა' },

  // Home Atmosphere Snippet
  'homeAtmosphere.subtitle': { en: 'Our Ambiance', ka: 'ჩვენი გარემო' },
  'homeAtmosphere.title': { en: 'Unique Atmosphere', ka: 'უნიკალური გარემო' },
  'homeAtmosphere.desc': { en: 'Step into a space where modern elegance meets traditional Georgian warmth. Every detail is crafted for your perfect dining experience.', ka: 'შედით სივრცეში, სადაც თანამედროვე ელეგანტურობა ხვდება ტრადიციულ ქართულ სითბოს. ყოველი დეტალი შექმნილია თქვენი იდეალური ვახშმისთვის.' },
  'homeAtmosphere.btn': { en: 'Explore', ka: 'დათვალიერება' }
};

export const LanguageProvider = ({ children }: { children: ReactNode }) => {
  const navigate = useNavigate();
  const location = useLocation();

  // Helper to extract language from path
  const getLangFromPath = (path: string): Language | null => {
    const match = path.match(/^\/(en|ka|ru)(\/|$)/);
    return match ? (match[1] as Language) : null;
  };

  // Get language from URL or localStorage or default to 'en'
  const getInitialLanguage = (): Language => {
    const urlLang = getLangFromPath(location.pathname);
    if (urlLang) {
      return urlLang;
    }
    const savedLang = localStorage.getItem('language') as Language;
    if (savedLang && LANGUAGES.includes(savedLang)) {
      return savedLang;
    }
    return 'en';
  };

  const [language, setLanguageState] = useState<Language>(getInitialLanguage());

  // Update URL and localStorage when language changes
  const setLanguage = (lang: Language) => {
    if (lang === language) return;

    setLanguageState(lang);
    localStorage.setItem('language', lang);

    // Get current path without language prefix
    const currentPath = location.pathname.replace(/^\/(en|ka|ru)/, '') || '/';

    // Navigate to new language URL
    // Ensure we don't double slash
    const newPath = `/${lang}${currentPath === '/' ? '' : currentPath}`;
    navigate(newPath + location.search + location.hash, { replace: true });
  };

  // Sync language with URL on route change
  useEffect(() => {
    const urlLang = getLangFromPath(location.pathname);
    if (urlLang && urlLang !== language) {
      setLanguageState(urlLang);
      localStorage.setItem('language', urlLang);
    } else if (!urlLang) {
      // If no language in URL, redirect to current language
      const currentPath = location.pathname === '/' ? '' : location.pathname;
      navigate(`/${language}${currentPath}${location.search}${location.hash}`, { replace: true });
    }
  }, [location.pathname, language, navigate]);

  const t = (key: string): string => {
    return translations[key]?.[language] || translations[key]?.en || key;
  };

  return (
    <LanguageContext.Provider value={{ language, setLanguage, t }}>
      {children}
    </LanguageContext.Provider>
  );
};

export const useLanguage = () => {
  const context = useContext(LanguageContext);
  if (context === undefined) {
    throw new Error('useLanguage must be used within a LanguageProvider');
  }
  return context;
};
