import { useState } from 'react';

interface ImageWithSkeletonProps extends React.ImgHTMLAttributes<HTMLImageElement> {
  containerClassName?: string;
  skeletonClassName?: string;
}

export default function ImageWithSkeleton({
  src,
  alt,
  className = '',
  containerClassName = '',
  skeletonClassName = 'bg-[#1a1a1a]',
  ...props
}: ImageWithSkeletonProps) {
  const [loaded, setLoaded] = useState(false);

  return (
    <div className={`relative w-full h-full ${containerClassName}`}>
      {/* Skeleton overlay */}
      {!loaded && (
        <div className={`absolute inset-0 animate-pulse z-0 ${skeletonClassName}`} />
      )}
      
      {/* Actual image */}
      <img
        src={src}
        alt={alt}
        onLoad={() => setLoaded(true)}
        className={`w-full h-full object-cover transition-opacity duration-1000 relative z-10 ${
          loaded ? className : 'opacity-0'
        }`}
        {...props}
      />
    </div>
  );
}
