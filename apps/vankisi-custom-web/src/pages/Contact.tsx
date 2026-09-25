import { useLanguage } from '../contexts/LanguageContext';
import Footer from '../components/Footer';

const Contact = () => {
  const { language, t } = useLanguage();

  // Scale down font size for Georgian language to match English visual weight
  const isGeorgian = language === 'ka';
  const baseFontSize = isGeorgian ? 'text-[1rem]' : 'text-[1rem]';

  return (
    <>
      <section id="contact" className={`min-h-screen bg-[#050505] pt-24 pb-16 md:pt-32 md:pb-32 relative font-sans text-white selection:bg-[#ae895e]/30 selection:text-[#ae895e] ${baseFontSize}`}>
        <div className="max-w-7xl mx-auto px-4 sm:px-6 md:px-8">
          <div className="text-center mb-16 md:mb-24 mt-8 md:mt-0">
            <h1 className="text-4xl md:text-5xl lg:text-7xl font-light tracking-wide text-white/95 mb-6">
              {t('contact.title')}
            </h1>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-20 items-stretch">

            {/* Left Column: Contact Info & Newsletter */}
            <div className="space-y-12 md:space-y-16">

              {/* Contact Info Blocks */}
              <div className="space-y-8 md:space-y-10">
                <div className="flex items-start gap-5 group transition-all duration-500 ease-out">
                  <div className="w-12 h-12 md:w-14 md:h-14 rounded-full border border-white/10 flex items-center justify-center flex-shrink-0 group-hover:border-[#ae895e] transition-colors bg-[#0a0a0a]">
                    <svg className="w-5 h-5 md:w-6 md:h-6 text-[#ae895e]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
                  </div>
                  <div>
                    <h4 className="text-[#ae895e] uppercase tracking-[0.2em] text-[10px] md:text-xs font-bold mb-2">{t('contact.address')}</h4>
                    <p className="text-white/80 font-light text-sm md:text-lg whitespace-pre-line leading-relaxed">{t('contact.address.value')}</p>
                  </div>
                </div>

                <div className="flex items-start gap-5 group transition-all duration-500 ease-out">
                  <div className="w-12 h-12 md:w-14 md:h-14 rounded-full border border-white/10 flex items-center justify-center flex-shrink-0 group-hover:border-[#ae895e] transition-colors bg-[#0a0a0a]">
                    <svg className="w-5 h-5 md:w-6 md:h-6 text-[#ae895e]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" /></svg>
                  </div>
                  <div>
                    <h4 className="text-[#ae895e] uppercase tracking-[0.2em] text-[10px] md:text-xs font-bold mb-2">{t('contact.phone')}</h4>
                    <p className="text-white/80 font-light text-sm md:text-lg">+995 599 98 93 76</p>
                    <p className="text-white/40 font-light text-xs mt-1">{t('contact.phone.availability')}</p>
                  </div>
                </div>

                <div className="flex items-start gap-5 group transition-all duration-500 ease-out">
                  <div className="w-12 h-12 md:w-14 md:h-14 rounded-full border border-white/10 flex items-center justify-center flex-shrink-0 group-hover:border-[#ae895e] transition-colors bg-[#0a0a0a]">
                    <svg className="w-5 h-5 md:w-6 md:h-6 text-[#ae895e]" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" /></svg>
                  </div>
                  <div>
                    <h4 className="text-[#ae895e] uppercase tracking-[0.2em] text-[10px] md:text-xs font-bold mb-2">{t('contact.email')}</h4>
                    <p className="text-white/80 font-light text-sm md:text-lg break-all">restaurantvankisi@gmail.com</p>
                    <p className="text-white/40 font-light text-xs mt-1">{t('contact.email.response')}</p>
                  </div>
                </div>
              </div>

              {/* Newsletter Box */}
              <div className="bg-[#0a0a0a] border border-white/5 p-6 md:p-10 shadow-xl relative overflow-hidden transition-all duration-500 ease-out">
                <div className="absolute -top-10 -right-10 opacity-5 pointer-events-none">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" className="w-40 h-40">
                    <path fill="#ae895e" d="M133 151L151 167Q167 177 187 184L226 195L231 195L236 197L241 197L246 199L264 202L268 204L272 204L302 214Q329 226 348 248L350 251L363 269L376 301L377 308L382 321L382 325L384 328L391 354L393 357L405 396L405 401L407 408L408 434L407 435L407 445L406 446L405 457L398 478L397 477L399 466L399 439L395 419L393 416L393 413L391 410L391 407L386 395L384 385L382 383L373 353L368 342L366 333L361 322L361 319L359 317L359 314Q347 286 327 268L324 266Q309 252 288 245L267 239L256 238L250 236L245 236L239 234L233 234L208 229L192 224L170 213L167 213Q168 210 165 211L147 196L135 174Q136 167 133 165L133 151Z" />
                  </svg>
                </div>
                <h3 className="text-xl md:text-2xl font-light text-white/95 mb-3 px-1">{t('contact.stayUpdated')}</h3>
                <p className="text-white/50 font-light text-xs md:text-sm leading-relaxed mb-6 px-1">
                  {t('contact.newsletter')}
                </p>
                <div className="flex flex-col gap-3">
                  <input
                    type="email"
                    placeholder={t('contact.email.placeholder')}
                    className="w-full bg-[#050505] border border-white/10 rounded p-4 text-white text-sm font-light focus:border-[#ae895e] outline-none transition-colors"
                  />
                  <button className="w-full bg-[#ae895e] text-black uppercase tracking-[0.2em] text-[10px] md:text-xs font-bold px-6 py-4 hover:bg-white transition-colors flex items-center justify-center gap-2 rounded cursor-pointer">
                    {t('contact.subscribe')} <svg className="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" /></svg>
                  </button>
                </div>
              </div>

            </div>

            {/* Right Column: Interactive Map Placeholder */}
            <div className="h-[400px] lg:h-auto min-h-[400px] lg:min-h-[600px] w-full relative transition-all duration-500 ease-out">
              <div className="absolute inset-0 bg-[#0a0a0a] border border-white/5 p-1.5 md:p-2 shadow-xl">
                {/* Google Maps iframe with dark mode filter */}
                <style dangerouslySetInnerHTML={{
                  __html: `
                  .map-dark-mode {
                    filter: grayscale(100%) invert(92%) contrast(83%);
                  }
                `}} />
                <iframe
                  src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d745.3958809332677!2d41.63812755920475!3d41.64313283907223!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x406787b46e4bb055%3A0x8ee65c5a2e766473!2sVankisi%20Restaurant!5e0!3m2!1sen!2sge!4v1756392250033!5m2!1sen!2sge"
                  width="100%"
                  height="100%"
                  style={{ border: 0 }}
                  allowFullScreen={true}
                  loading="lazy"
                  referrerPolicy="no-referrer-when-downgrade"
                  className="map-dark-mode rounded-sm"
                  title="Restaurant Vankisi Location"
                ></iframe>
              </div>
            </div>

          </div>
        </div>
      </section>
      <Footer />
    </>
  );
};

export default Contact;
