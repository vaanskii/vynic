import { useEffect, useState, useRef } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import floor1SvgUrl from '../assets/floor1.svg';
import floor2SvgUrl from '../assets/floor2.svg';
import styles from '../css/SelectTable.module.css';
import { useLanguage } from '../contexts/LanguageContext';
import { tableService } from '../services/api';
import { useCart } from '../contexts/CartContext';
import DatePicker from 'react-datepicker';
import 'react-datepicker/dist/react-datepicker.css';

// Custom styles for DatePicker
const datePickerStyles = `
  .react-datepicker-custom {
    background-color: #333 !important;
    border: 1px solid #a89763 !important;
    border-radius: 0.5rem !important;
    color: #a89763 !important;
  }
  
  .react-datepicker-custom .react-datepicker__header {
    background-color: #a89763 !important;
    border-bottom: 1px solid #a89763 !important;
    border-radius: 0.5rem 0.5rem 0 0 !important;
  }
  
  .react-datepicker-custom .react-datepicker__current-month,
  .react-datepicker-custom .react-datepicker__day-name {
    color: #222 !important;
    font-weight: bold !important;
  }
  
  .react-datepicker-custom .react-datepicker__day {
    color: #a89763 !important;
    background-color: transparent !important;
  }
  
  .react-datepicker-custom .react-datepicker__day:hover {
    background-color: #a89763 !important;
    color: #222 !important;
    border-radius: 0.25rem !important;
  }
  
  .react-datepicker-custom .react-datepicker__day--selected {
    background-color: #c0ad7b !important;
    color: #222 !important;
    border-radius: 0.25rem !important;
  }
  
  .react-datepicker-custom .react-datepicker__day--disabled {
    color: #666 !important;
    cursor: not-allowed !important;
  }
  
  .react-datepicker-custom .react-datepicker__navigation {
    border: none !important;
  }
  
  .react-datepicker-custom .react-datepicker__navigation--previous {
    border-right-color: #222 !important;
  }
  
  .react-datepicker-custom .react-datepicker__navigation--next {
    border-left-color: #222 !important;
  }
`;

// Inject styles
if (typeof document !== 'undefined') {
  const styleElement = document.createElement('style');
  styleElement.textContent = datePickerStyles;
  document.head.appendChild(styleElement);
}

const CreateOrder = () => {
  const { t, language } = useLanguage();
  const navigate = useNavigate();
  const location = useLocation();
  const [currentFloor, setCurrentFloor] = useState<'floor1' | 'floor2'>('floor1');
  const [svgContent, setSvgContent] = useState<string>('');
  const [svgIds, setSvgIds] = useState<string[]>([]);
  const [selectedTables, setSelectedTables] = useState<Set<string>>(new Set());
  const [selectedDate, setSelectedDate] = useState<string>('');
  const [selectedTime, setSelectedTime] = useState<string>('');
  const [takenTables, setTakenTables] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSvgLoaded, setIsSvgLoaded] = useState<boolean>(false);
  const [isDataLoaded, setIsDataLoaded] = useState<boolean>(false);
  const svgRef = useRef<HTMLDivElement>(null);
  const { } = useCart();

  // Step state: 'datetime' or 'table'
  const [step, setStep] = useState<'datetime' | 'table'>('datetime');

  // Temporary state for date/time selection in step 1
  const [tempDate, setTempDate] = useState<string>('');
  const [tempTime, setTempTime] = useState<string>('');

  // Function to load SVG content based on current floor
  const loadFloorSvg = async (floor: 'floor1' | 'floor2') => {
    const svgUrl = floor === 'floor1' ? floor1SvgUrl : floor2SvgUrl;

    try {
      const response = await fetch(svgUrl);
      const svgText = await response.text();
      setSvgContent(svgText);

      // Extract all IDs from the SVG
      const idMatches = svgText.match(/id="([^"]+)"/g) || [];
      const ids = idMatches.map(match => match.replace(/id="([^"]+)"/, '$1'));

      let selectableIds: string[] = [];

      if (floor === 'floor1') {
        // Filter table IDs for floor 1 (looking for table1-table11 pattern)
        selectableIds = ids.filter(id => /^table\d{1,2}$/i.test(id));
      } else {
        // For floor 2, look for vip-zone-1, vip-zone-2, vip-zone-3
        selectableIds = ids.filter(id => /^vip-zone-\d+$/i.test(id));
      }

      setSvgIds(selectableIds);
      console.log(`Found ${floor} selectable IDs:`, selectableIds);

      // Mark SVG as loaded
      setIsSvgLoaded(true);
    } catch (error) {
      console.error(`Error loading ${floor} SVG:`, error);
      // Even on error, mark as loaded to prevent infinite loading
      setIsSvgLoaded(true);
    }
  };

  // Function to switch floors
  const switchFloor = (floor: 'floor1' | 'floor2') => {
    if (floor !== currentFloor) {
      setCurrentFloor(floor);
      setIsSvgLoaded(false);

      // Clear current selections when switching floors
      // setSelectedTables(new Set());

      // Load the new floor SVG
      loadFloorSvg(floor);
    }
  };
  const fetchTableAvailability = async (date: string) => {
    if (!date) {
      setTakenTables(new Set());
      setIsDataLoaded(true);
      return;
    }

    console.log('=== DEBUGGING TABLE AVAILABILITY ===');
    console.log('Fetching table availability for date:', date);
    console.log('API Base URL will be:', `${window.location.protocol}//${window.location.hostname}:3000/api`);

    try {
      const availability = await tableService.getTableAvailability(date);
      console.log('API Response:', availability);
      console.log('API Response length:', availability.length);

      // Availability returns array of {tableNumber, isAvailable}
      const taken = new Set<string>(
        availability
          .filter((table: { tableNumber: string; isAvailable: boolean }) => !table.isAvailable)
          .map((table: { tableNumber: string; isAvailable: boolean }) => table.tableNumber)
      );
      console.log('Filtered unavailable tables:', Array.from(taken));
      console.log('Setting takenTables to:', Array.from(taken));
      setTakenTables(taken);
    } catch (error) {
      console.error('Error fetching table availability:', error);
      console.error('Error details:', error);
      // On error, assume all tables are available (empty set means no tables are taken)
      setTakenTables(new Set());
      console.log('API call failed, assuming all tables are available');
    } finally {
      setIsDataLoaded(true);
    }
  };

  // Function to load initial data (extracted for reuse)
  const loadInitialData = async () => {
    const EXPIRATION_TIME = 2 * 60 * 60 * 1000; // 2 hours in milliseconds
    const now = Date.now();

    const savedReservationData = localStorage.getItem('reservationData');

    if (savedReservationData) {
      try {
        const parsedData = JSON.parse(savedReservationData);

        // Check for expiration
        if (parsedData.timestamp && (now - parsedData.timestamp > EXPIRATION_TIME)) {
          console.log('Saved reservation data expired, clearing...');
          localStorage.removeItem('reservationData');
          localStorage.removeItem('selectedReservationDate');
          localStorage.removeItem('selectedReservationTime');
          // Set tomorrow as default date
          const tomorrowDate = getTomorrowGeorgiaDate();
          setTempDate(tomorrowDate);
          console.log('Default date set to:', tomorrowDate);
          setIsDataLoaded(true);
          return;
        }

        console.log('Loading saved reservation data:', parsedData);

        // Restore selected tables
        if (parsedData.selectedTables && Array.isArray(parsedData.selectedTables)) {
          setSelectedTables(new Set(parsedData.selectedTables));
          console.log('Restored selected tables:', parsedData.selectedTables);
        }

        // Restore floor information
        if (parsedData.currentFloor && (parsedData.currentFloor === 'floor1' || parsedData.currentFloor === 'floor2')) {
          setCurrentFloor(parsedData.currentFloor);
          console.log('Restored floor:', parsedData.currentFloor);
          // Load the correct floor SVG
          loadFloorSvg(parsedData.currentFloor);
        }

        // Restore date and time from reservation data if available
        if (parsedData.selectedDate && parsedData.selectedTime) {
          setSelectedDate(parsedData.selectedDate);
          setSelectedTime(parsedData.selectedTime);
          setTempDate(parsedData.selectedDate);
          setTempTime(parsedData.selectedTime);

          console.log('Restored date/time from reservation data:', parsedData.selectedDate, parsedData.selectedTime);

          // If we have date/time, we can go to step 2 directly
          setStep('table');

          // Fetch table availability AFTER restoring selected tables
          await fetchTableAvailability(parsedData.selectedDate);
          return; // Exit early, we have all the data we need
        }
      } catch (error) {
        console.error('Error parsing saved reservation data:', error);
      }
    }

    // If no reservation data (or expired), check individual localStorage items (legacy support or fallback)
    const savedDate = localStorage.getItem('selectedReservationDate');
    const savedTime = localStorage.getItem('selectedReservationTime');

    if (savedDate && savedTime) {
      console.log('Loading saved date/time from individual localStorage items:', savedDate, savedTime);
      setSelectedDate(savedDate);
      setSelectedTime(savedTime);
      setTempDate(savedDate);
      setTempTime(savedTime);

      // If we have date/time, we can go to step 2 directly
      setStep('table');

      // Fetch table availability immediately for the saved date
      await fetchTableAvailability(savedDate);
    } else {
      // No saved data, set tomorrow as default date
      console.log('No saved data found, setting tomorrow as default date');
      const tomorrowDate = getTomorrowGeorgiaDate();
      setTempDate(tomorrowDate);
      console.log('Default date set to:', tomorrowDate);
      setIsDataLoaded(true);
    }
  };

  // Load saved date and time from localStorage on component mount
  useEffect(() => {
    loadInitialData();
  }, []);

  // Reload data when navigating to this page from another route
  useEffect(() => {
    // Only reload if this is not the initial mount (location.key changes on navigation)
    const isInitialMount = location.key === 'default';
    if (!isInitialMount) {
      console.log('Navigation detected, checking if reload is needed');

      // Check if we actually have data that needs to be reloaded
      const savedDate = localStorage.getItem('selectedReservationDate');
      const savedTime = localStorage.getItem('selectedReservationTime');
      const savedReservationData = localStorage.getItem('reservationData');

      // Only reload if we have saved data to restore
      if (savedDate || savedTime || savedReservationData) {
        console.log('Found saved data, reloading SelectTable data');
        // Reset loading states to ensure fresh data load
        setIsLoading(true);
        setIsDataLoaded(false);

        // Reload the data
        loadInitialData();
      } else {
        console.log('No saved data found, skipping reload on navigation');
        // Just ensure we're marked as loaded since there's nothing to fetch
        setIsDataLoaded(true);
      }
    }
  }, [location.key]);


  useEffect(() => {
    // Load the initial floor SVG
    loadFloorSvg(currentFloor);
  }, [currentFloor]);

  // Manage overall loading state
  useEffect(() => {
    if (isSvgLoaded && isDataLoaded) {
      setIsLoading(false);
      console.log('All data loaded, hiding loader');
    }
  }, [isSvgLoaded, isDataLoaded]);

  // Re-apply styles when SVG is loaded and IDs are available
  useEffect(() => {
    if (svgContent && svgIds.length > 0) {
      console.log('SVG loaded, applying styles. Selected tables:', Array.from(selectedTables), 'Taken tables:', Array.from(takenTables));
      // Force re-render of styles after SVG is loaded
      const timeoutId = setTimeout(() => {
        if (svgRef.current) {
          // Reset all table styles first
          svgIds.forEach(tableId => {
            const tableElement = svgRef.current!.querySelector(`#${tableId}`);
            if (tableElement) {
              tableElement.classList.remove('table-selected', 'table-taken');
            }
          });

          // Apply taken table styles first
          takenTables.forEach((tableId: string) => {
            const tableElement = svgRef.current!.querySelector(`#${tableId}`);
            if (tableElement) {
              tableElement.classList.add('table-taken');
              console.log('Applied taken style to:', tableId);
            }
          });

          // Then apply selected styles (will override taken if there's a conflict)
          selectedTables.forEach(tableId => {
            const tableElement = svgRef.current!.querySelector(`#${tableId}`);
            if (tableElement && !takenTables.has(tableId)) {
              tableElement.classList.add('table-selected');
              console.log('Applied selected style to:', tableId);
            }
          });
        }
      }, 150);

      return () => clearTimeout(timeoutId);
    }
  }, [svgContent, svgIds, selectedTables, takenTables]);

  const handleTableClick = (event: React.MouseEvent<HTMLDivElement>) => {
    const target = event.target as SVGElement;

    // Try to find the selectable ID by checking the clicked element and its parents
    let selectableId = null;
    let currentElement = target;

    // Check up to 5 levels up the DOM tree to find a selectable ID
    for (let i = 0; i < 5 && currentElement; i++) {
      const id = currentElement.getAttribute('id');
      if (id) {
        // Check if it's a table (floor 1) or vip zone (floor 2)
        const isTable = /^table\d{1,2}$/i.test(id);
        const isVipZone = /^vip-zone-\d+$/i.test(id);

        if ((currentFloor === 'floor1' && isTable) || (currentFloor === 'floor2' && isVipZone)) {
          selectableId = id;
          break;
        }
      }
      currentElement = currentElement.parentElement as unknown as SVGElement;
    }

    console.log('Clicked element:', target.tagName, 'Found selectable ID:', selectableId, 'Floor:', currentFloor);

    if (selectableId) {
      console.log('Current taken items:', Array.from(takenTables));
      console.log('Is item taken?', takenTables.has(selectableId));

      // Don't allow selection of taken items (booked for entire day)
      if (takenTables.has(selectableId)) {
        console.log('Item is taken for this date:', selectableId);
        return;
      }

      // Toggle selection
      setSelectedTables(prev => {
        const newSet = new Set(prev);
        if (newSet.has(selectableId)) {
          newSet.delete(selectableId);
          console.log('Deselected item:', selectableId);
        } else {
          newSet.add(selectableId);
          console.log('Selected item:', selectableId);
        }
        return newSet;
      });
    }
  };

  // Apply styles to selected tables
  useEffect(() => {
    if (svgContent && svgRef.current && svgIds.length > 0) {
      // Add a small delay to ensure SVG is fully rendered
      const timeoutId = setTimeout(() => {
        const svgContainer = svgRef.current;
        if (!svgContainer) return;

        console.log('Applying styles to tables:', {
          selectedTables: Array.from(selectedTables),
          takenTables: Array.from(takenTables),
          svgIds: svgIds
        });

        // Reset all table styles first
        svgIds.forEach(tableId => {
          const tableElement = svgContainer.querySelector(`#${tableId}`);
          if (tableElement) {
            tableElement.classList.remove('table-selected', 'table-taken');
          }
        });

        // Apply taken table styles (red)
        takenTables.forEach((tableId: string) => {
          const tableElement = svgContainer.querySelector(`#${tableId}`);
          if (tableElement) {
            tableElement.classList.add('table-taken');
            console.log('Applied taken style to:', tableId);
          }
        });

        // Apply selected styles (blue/green)
        selectedTables.forEach(tableId => {
          const tableElement = svgContainer.querySelector(`#${tableId}`);
          if (tableElement && !takenTables.has(tableId)) {
            tableElement.classList.add('table-selected');
            console.log('Applied selected style to:', tableId);
          }
        });
      }, 100); // Small delay to ensure SVG is rendered

      return () => clearTimeout(timeoutId);
    }
  }, [selectedTables, svgContent, svgIds, takenTables]);

  const clearSelection = () => {
    console.log('Clearing table selection');
    setSelectedTables(new Set());
    // Update reservation data in localStorage to reflect cleared selection
    if (selectedDate && selectedTime) {
      const reservationData = {
        selectedTables: [],
        selectedDate,
        selectedTime,
        currentFloor, // Include current floor
      };
      localStorage.setItem('reservationData', JSON.stringify(reservationData));
      console.log('Updated localStorage with cleared selection:', reservationData);
    }
  };


  // Clear selection when date changes (but not during initial load)
  useEffect(() => {
    // Only clear if we have a previous date and it's changing to a new date
    // Don't clear during initial load from localStorage
    if (selectedDate) {
      const savedReservationData = localStorage.getItem('reservationData');
      if (savedReservationData) {
        try {
          const parsedData = JSON.parse(savedReservationData);
          // If this is not the same date as saved, then clear tables
          if (parsedData.selectedDate && parsedData.selectedDate !== selectedDate) {
            console.log('Date changed from saved data, clearing selected tables');
            setSelectedTables(new Set());
          }
        } catch (error) {
          console.error('Error parsing saved data during date change:', error);
        }
      }
    }
  }, [selectedDate]);

  const handleDateSelect = (date: string) => {
    setTempDate(date);
  };

  const handleTimeSelect = (time: string) => {
    setTempTime(time);
  };

  const handleContinueToTables = async () => {
    console.log('handleContinueToTables called with:', tempDate, tempTime);

    if (tempDate && tempTime) {
      console.log('Confirming and saving date and time to localStorage:', tempDate, tempTime);

      // Check if date or time has changed
      if (tempDate !== selectedDate || tempTime !== selectedTime) {
        // If changed, clear selected tables
        setSelectedTables(new Set());
      }

      // Apply the temporary values to actual state
      setSelectedDate(tempDate);
      setSelectedTime(tempTime);

      // Save selected date and time to localStorage
      localStorage.setItem('selectedReservationDate', tempDate);
      localStorage.setItem('selectedReservationTime', tempTime);

      // Fetch availability immediately with the confirmed date
      setIsLoading(true);
      await fetchTableAvailability(tempDate);
      setIsLoading(false);

      // Move to next step
      setStep('table');
    } else {
      console.log('Missing date or time:', { tempDate, tempTime });
      alert('Please select both date and time before confirming.');
    }
  };

  const handleBackToDateTime = () => {
    setStep('datetime');
  };

  // Function to save current reservation data to localStorage
  const saveReservationData = () => {
    if (selectedDate && selectedTime) {
      const reservationData = {
        selectedTables: Array.from(selectedTables),
        selectedDate,
        selectedTime,
        currentFloor, // Save the current floor
        timestamp: Date.now(), // Add timestamp for expiration
      };
      localStorage.setItem('reservationData', JSON.stringify(reservationData));
      console.log('Saved reservation data to localStorage:', reservationData);
    }
  };

  // Save reservation data whenever tables, date, or time changes
  useEffect(() => {
    if (selectedDate && selectedTime) {
      saveReservationData();
    }
  }, [selectedTables, selectedDate, selectedTime]);

  // Function to proceed to menu with selected tables
  const proceedToMenu = () => {
    if (selectedTables.size === 0) return;

    // Save reservation details to localStorage (this is redundant now but kept for clarity)
    saveReservationData();

    // Navigate to menu page
    navigate(`/${language}/menu`);
  };

  const formatTableName = (itemId: string): string => {
    // Handle table format (table1, table2, etc.)
    const tableMatch = itemId.match(/^table(\d{1,2})$/i);
    if (tableMatch) {
      return `Table ${tableMatch[1]}`;
    }

    // Handle VIP zone format (vip-zone-1, vip-zone-2, etc.)
    const vipMatch = itemId.match(/^vip-zone-(\d+)$/i);
    if (vipMatch) {
      return `VIP Zone ${vipMatch[1]}`;
    }

    // Fallback to capitalize first letter
    return itemId.charAt(0).toUpperCase() + itemId.slice(1);
  }

  const getTomorrowGeorgiaDate = () => {
    const now = new Date();
    // Add one day in milliseconds
    const tomorrow = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const tomorrowDate = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Tbilisi',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(tomorrow);

    return tomorrowDate;
  }

  return (
    <>
      {/* Full Page Loader */}
      {isLoading && (
        <div className="fixed inset-0 bg-[#222]/50 z-50 flex items-center justify-center">
          <div className="text-center">
            <div className="relative">
              {/* Spinning loader */}
              <div className="w-16 h-16 border-4 border-[#333] border-t-[#a89763] rounded-full animate-spin mx-auto mb-4"></div>

              {/* Pulsing inner circle */}
              <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-8 h-8 bg-[#a89763] rounded-full animate-pulse opacity-50"></div>
            </div>

            <h3 className="text-xl font-semibold text-[#a89763] mb-2">
              {language === 'ka' ? 'მაგიდების რუქა იტვირთება...' : 'Loading Table Layout...'}
            </h3>
            <p className="text-gray-400 text-sm">
              {language === 'ka'
                ? 'გთხოვთ მოითმინოთ, ჩვენ ვტვირთავთ ხელმისაწვდომ მაგიდებს'
                : 'Please wait while we load available tables'
              }
            </p>

            {/* Progress indicator */}
            <div className="mt-4 flex justify-center space-x-1">
              <div className="w-2 h-2 bg-[#a89763] rounded-full animate-bounce"></div>
              <div className="w-2 h-2 bg-[#a89763] rounded-full animate-bounce" style={{ animationDelay: '0.1s' }}></div>
              <div className="w-2 h-2 bg-[#a89763] rounded-full animate-bounce" style={{ animationDelay: '0.2s' }}></div>
            </div>
          </div>
        </div>
      )}

      {/* Main Content */}
      <div id="reservation-page" className="text-white md:py-40 py-50 flex justify-center items-center flex-col min-h-screen">

        {/* Step 1: Date and Time Selection */}
        {step === 'datetime' && (
          <div className="w-full max-w-md p-8 bg-[#333] rounded-xl shadow-2xl border border-[#a89763]/30 animate-fade-in">
            <h2 className="text-3xl font-bold text-[#a89763] mb-4 text-center font-rosset">
              {language === 'ka' ? 'აირჩიეთ დრო' : 'Select Date & Time'}
            </h2>

            <p className="text-sm text-gray-400 text-center mb-8 leading-relaxed">
              {language === 'ka'
                ? 'გთხოვთ აირჩიოთ სასურველი თარიღი და დრო მაგიდების ხელმისაწვდომობის შესასამოწმებლად.'
                : 'Please select your preferred date and time to check table availability.'
              }
            </p>

            <div className="space-y-8">
              <div>
                <label className="block text-sm font-medium mb-3 text-[#a89763] uppercase tracking-wider">
                  {language === 'ka' ? 'თარიღი' : 'Date'}
                </label>
                <DatePicker
                  selected={tempDate ? new Date(tempDate + 'T00:00:00') : null}
                  onChange={(date) => {
                    if (date) {
                      // Use local date formatting to avoid timezone issues
                      const year = date.getFullYear();
                      const month = String(date.getMonth() + 1).padStart(2, '0');
                      const day = String(date.getDate()).padStart(2, '0');
                      const formattedDate = `${year}-${month}-${day}`;
                      handleDateSelect(formattedDate);
                    }
                  }}
                  minDate={new Date(getTomorrowGeorgiaDate() + 'T00:00:00')}
                  dateFormat="yyyy-MM-dd"
                  placeholderText={language === 'ka' ? 'აირჩიეთ თარიღი' : 'Select a date'}
                  className="w-full px-4 py-4 bg-[#222] border border-[#a89763] rounded-lg text-[#a89763] text-lg focus:outline-none cursor-pointer transition-colors focus:border-[#c0ad7b]"
                  calendarClassName="react-datepicker-custom"
                  wrapperClassName="w-full"
                  onKeyDown={(e) => {
                    e.preventDefault();
                  }}
                  autoComplete="off"
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-3 text-[#a89763] uppercase tracking-wider">
                  {language === 'ka' ? 'დრო' : 'Time'}
                </label>
                <select
                  value={tempTime}
                  onChange={(e) => handleTimeSelect(e.target.value)}
                  className="w-full px-4 py-4 bg-[#222] border border-[#a89763] rounded-lg text-[#a89763] text-lg focus:outline-none cursor-pointer appearance-none transition-colors focus:border-[#c0ad7b]"
                  required
                >
                  <option value="">{language === 'ka' ? 'აირჩიეთ საათი' : 'Select time slot'}</option>
                  <option value="10:00">10:00 AM</option>
                  <option value="11:00">11:00 AM</option>
                  <option value="12:00">12:00 PM</option>
                  <option value="13:00">1:00 PM</option>
                  <option value="14:00">2:00 PM</option>
                  <option value="15:00">3:00 PM</option>
                  <option value="16:00">4:00 PM</option>
                  <option value="17:00">5:00 PM</option>
                  <option value="18:00">6:00 PM</option>
                  <option value="19:00">7:00 PM</option>
                  <option value="20:00">8:00 PM</option>
                  <option value="21:00">9:00 PM</option>
                  <option value="22:00">10:00 PM</option>
                </select>
              </div>

              {tempDate && tempTime && (
                <div className="p-4 bg-[#a89763]/10 border border-[#a89763] rounded-lg animate-fade-in">
                  <p className="text-sm text-[#e0e0e0] text-center">
                    {language === 'ka' ? 'რეზერვაცია:' : 'Reservation for:'} <br />
                    <span className="text-[#a89763] font-bold text-lg">{tempDate}</span> at <span className="text-[#a89763] font-bold text-lg">{tempTime}</span>
                  </p>
                </div>
              )}

              <button
                onClick={handleContinueToTables}
                disabled={!tempDate || !tempTime}
                className={`w-full py-4 rounded-lg font-bold text-lg uppercase tracking-wider transition-all duration-300 transform 
                  ${tempDate && tempTime
                    ? 'bg-gradient-to-r from-[#a89763] to-[#c0ad7b] text-[#222] hover:scale-105 hover:shadow-lg cursor-pointer'
                    : 'bg-[#444] text-gray-500 cursor-not-allowed'}`}
              >
                {language === 'ka' ? 'გაგრძელება' : 'Continue'}
              </button>

              {(tempDate || tempTime) && (
                <button
                  onClick={() => {
                    setTempDate('');
                    setTempTime('');
                    setSelectedDate('');
                    setSelectedTime('');
                    localStorage.removeItem('selectedReservationDate');
                    localStorage.removeItem('selectedReservationTime');
                    localStorage.removeItem('reservationData');
                  }}
                  className="w-full py-3 rounded-lg font-medium text-sm uppercase tracking-wider transition-all duration-300 bg-[#222] border border-red-500/50 text-red-400 hover:bg-red-900/20 cursor-pointer"
                >
                  {language === 'ka' ? 'გასუფთავება' : 'Clear Selection'}
                </button>
              )}
            </div>
          </div>
        )}

        {/* Step 2: Table Selection */}
        {step === 'table' && (
          <div className="animate-fade-in w-full mt-[-80px] md:mt-[-20px] flex flex-col items-center">

            {/* Header with Back Button and Info */}
            <div className="w-full max-w-6xl px-4 mb-4 flex flex-col md:flex-row justify-between items-center gap-4">
              <button
                onClick={handleBackToDateTime}
                className="flex items-center gap-2 text-[#a89763] hover:text-[#c0ad7b] transition-colors cursor-pointer self-start md:self-auto"
              >
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clipRule="evenodd" />
                </svg>
                {language === 'ka' ? 'უკან' : 'Back'}
              </button>

              <div className="flex items-center gap-3 bg-[#333] px-4 py-1 rounded-full border border-[#a89763]/30">
                <span className="text-[#e0e0e0] font-medium text-sm">{selectedDate}</span>
                <span className="text-[#a89763]">•</span>
                <span className="text-[#e0e0e0] font-medium text-sm">{selectedTime}</span>
                <button
                  onClick={handleBackToDateTime}
                  className="ml-2 text-xs text-[#a89763] hover:underline cursor-pointer"
                >
                  {language === 'ka' ? 'შეცვლა' : 'Change'}
                </button>
              </div>

              <div className="w-20 hidden md:block"></div> {/* Spacer for centering */}
            </div>

            <div className="w-full flex flex-col items-center">
              <div className="flex flex-col items-center relative w-full">
                <h2 className="text-xl mb-2 text-center w-full font-rosset text-[#a89763]">
                  {t('selectTable.title')}
                </h2>

                {/* Floor Selection Buttons */}
                <div className="mb-4 flex gap-3 w-full justify-center">
                  <button
                    onClick={() => switchFloor('floor1')}
                    className={`px-4 py-2 rounded-lg text-xs font-bold uppercase tracking-wider transition-all cursor-pointer border ${currentFloor === 'floor1'
                      ? 'bg-[#a89763] text-[#222] border-[#a89763]'
                      : 'bg-[#222] text-[#a89763] border-[#a89763] hover:bg-[#333]'
                      }`}
                  >
                    {language === 'ka' ? 'პირველი სართული' : 'First Floor'}
                  </button>
                  <button
                    onClick={() => switchFloor('floor2')}
                    className={`px-4 py-2 rounded-lg text-xs font-bold uppercase tracking-wider transition-all cursor-pointer border ${currentFloor === 'floor2'
                      ? 'bg-[#c0a965] text-[#222] border-[#c0a965]'
                      : 'bg-[#222] text-[#c0a965] border-[#c0a965] hover:bg-[#333]'
                      }`}
                  >
                    {language === 'ka' ? 'მეორე სართული (VIP)' : 'Second Floor (VIP)'}
                  </button>
                </div>

                {/* Legend */}
                <div className="mb-4 w-full flex justify-center">
                  <div className="flex flex-wrap gap-4 text-xs bg-[#333] px-4 py-2 rounded-lg border border-[#444]">
                    <div className="flex items-center gap-2">
                      <div className="w-3 h-3 bg-white rounded border border-gray-500"></div>
                      <span className="text-gray-300">
                        {currentFloor === 'floor1'
                          ? (language === 'ka' ? 'ხელმისაწვდომი' : 'Available')
                          : (language === 'ka' ? 'ხელმისაწვდომი' : 'Available')
                        }
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-3 h-3 bg-[#c0ad7b] rounded"></div>
                      <span className="text-[#c0ad7b] font-medium">
                        {currentFloor === 'floor1'
                          ? (language === 'ka' ? 'არჩეული' : 'Selected')
                          : (language === 'ka' ? 'არჩეული' : 'Selected')
                        }
                      </span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-3 h-3 bg-red-500 rounded"></div>
                      <span className="text-red-400">
                        {currentFloor === 'floor1'
                          ? (language === 'ka' ? 'დაჯავშნული' : 'Booked')
                          : (language === 'ka' ? 'დაჯავშნული' : 'Booked')
                        }
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* SVG Container */}
              <div className={`${styles.svgContainer} transition-opacity duration-500 mb-6 mt-6`}>
                {svgContent && (
                  <div
                    ref={svgRef}
                    dangerouslySetInnerHTML={{ __html: svgContent }}
                    onClick={handleTableClick}
                    className="cursor-pointer"
                  />
                )}
              </div>

              {selectedTables.size > 0 && (
                <div className="w-[90%] max-w-4xl mx-auto animate-fade-in mb-8">
                  <div className="bg-[#222] rounded-xl p-4 shadow-lg flex flex-col md:flex-row justify-between items-center gap-4">
                    <div className="flex flex-col gap-1">
                      <h3 className="text-[#a89763] font-semibold text-xs uppercase tracking-wider text-center md:text-left">
                        {currentFloor === 'floor1'
                          ? (language === 'ka' ? 'არჩეული მაგიდები:' : 'Selected Tables:')
                          : (language === 'ka' ? 'არჩეული VIP ზონები:' : 'Selected VIP Zones:')
                        }
                      </h3>
                      <div className="flex flex-wrap justify-center md:justify-start gap-2">
                        {Array.from(selectedTables).map(itemId => (
                          <span key={itemId} className="bg-[#c0ad7b] text-[#222] px-2 py-1 rounded font-bold text-xs">
                            {formatTableName(itemId)}
                          </span>
                        ))}
                      </div>
                    </div>

                    <div className="flex gap-3 w-full md:w-auto">
                      <button
                        onClick={clearSelection}
                        className="flex-1 md:flex-none bg-[#333] border border-red-500/50 hover:bg-red-900/20 text-red-400 px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer"
                      >
                        {language === 'ka' ? 'გასუფთავება' : 'Clear'}
                      </button>
                      <button
                        onClick={proceedToMenu}
                        className="flex-1 md:flex-none bg-gradient-to-r from-[#a89763] to-[#c0ad7b] hover:from-[#c0ad7b] hover:to-[#a89763] text-[#222] font-bold px-6 py-2 rounded-lg text-sm transition-all duration-300 flex items-center justify-center gap-2 cursor-pointer shadow-lg hover:shadow-[#a89763]/20"
                      >
                        {language === 'ka' ? 'მენიუს არჩევა' : 'Continue'}
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </>
  );
}

export default CreateOrder;