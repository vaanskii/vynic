import { useState, useEffect } from 'react';
import '../css/Loader.css';

interface LoaderProps {
  onLoadComplete: () => void;
}

const Loader = ({ onLoadComplete }: LoaderProps) => {
  const [isLoading, setIsLoading] = useState(true);
  const [fadeOut, setFadeOut] = useState(false);
  const [loadingProgress, setLoadingProgress] = useState(0);

  useEffect(() => {
    // Simulate loading progress
    const progressInterval = setInterval(() => {
      setLoadingProgress(prev => {
        if (prev >= 100) {
          clearInterval(progressInterval);
          return 100;
        }
        return prev + Math.random() * 15; // Random increment for realistic feel
      });
    }, 100);

    // Check if page is ready
    const checkPageReady = () => {
      if (document.readyState === 'complete' && loadingProgress >= 100) {
        // Start fade out animation
        setFadeOut(true);
        
        // Complete loading after fade animation
        setTimeout(() => {
          setIsLoading(false);
          onLoadComplete();
        }, 500); // 500ms for fade out animation
      }
    };

    // Minimum loading time of 1.5 seconds
    const minLoadingTimer = setTimeout(() => {
      if (document.readyState === 'complete') {
        setLoadingProgress(100);
        checkPageReady();
      } else {
        // If page isn't ready, keep checking
        const readyStateInterval = setInterval(() => {
          if (document.readyState === 'complete') {
            setLoadingProgress(100);
            clearInterval(readyStateInterval);
            checkPageReady();
          }
        }, 100);
      }
    }, 1500);

    return () => {
      clearTimeout(minLoadingTimer);
      clearInterval(progressInterval);
    };
  }, [onLoadComplete, loadingProgress]);

  if (!isLoading) return null;

  return (
    <div 
      className={`fixed inset-0 z-50 flex items-center justify-center bg-[#222] transition-opacity duration-500 ${
        fadeOut ? 'opacity-0' : 'opacity-100'
      }`}
    >
      <div className="flex flex-col items-center space-y-8">
        {/* Logo with pulsing animation */}
        <div className="relative">
          <img 
            src="/full-logo.png" 
            alt="Vankisi Restaurant" 
            className="w-24 h-24 sm:w-32 sm:h-32 lg:w-40 lg:h-40 object-contain animate-pulse"
          />
         
        </div>

        {/* Loading text with dots animation */}
        <div className="text-center">
          <p className="text-[#a89763] text-lg font-light">
            Preparing your experience<span className="loading-dots">...</span>
          </p>
        </div>

        {/* Loading bar */}
        <div className="w-64 h-2 bg-[#333] rounded-full overflow-hidden">
          <div 
            className="h-full bg-gradient-to-r from-[#e9caa2] to-[#cba76d] transition-all duration-300 ease-out rounded-full"
            style={{ width: `${Math.min(loadingProgress, 100)}%` }}
          ></div>
        </div>
      </div>
    </div>
  );
};

export default Loader;
