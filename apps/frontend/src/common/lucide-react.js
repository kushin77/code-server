/**
 * Icon components (lucide-react stub implementation)
 * Provides SVG icon components for UI
 */
import React from 'react';
// AlertTriangle
export const AlertTriangle = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-alert-triangle ${className}`}>
    <path d="M10.24 3.957l-8.422 14.06A1.989 1.989 0 0 0 3.482 21h16.036a1.989 1.989 0 0 0 1.74-3.183L13.76 3.957a1.989 1.989 0 0 0-3.52 0z"/>
    <path d="M12 9v6M12 21h.01"/>
  </svg>);
// CheckCircle
export const CheckCircle = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-check-circle ${className}`}>
    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
    <polyline points="22 4 12 14.01 9 11.01"/>
  </svg>);
// Clock
export const Clock = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-clock ${className}`}>
    <circle cx="12" cy="12" r="10"/>
    <polyline points="12 6 12 12 16 14"/>
  </svg>);
// ExternalLink
export const ExternalLink = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-external-link ${className}`}>
    <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3"/>
  </svg>);
// RefreshCw
export const RefreshCw = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-refresh-cw ${className}`}>
    <polyline points="23 4 23 10 17 10M1 20 1 14 7 14M3.51 9a9 9 0 0 1 14.85-3.36M20.49 15a9 9 0 0 1-14.85 3.36"/>
  </svg>);
// AlertCircle
export const AlertCircle = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-alert-circle ${className}`}>
    <circle cx="12" cy="12" r="10"/>
    <line x1="12" y1="8" x2="12" y2="12"/>
    <line x1="12" y1="16" x2="12.01" y2="16"/>
  </svg>);
// ChevronDown
export const ChevronDown = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-chevron-down ${className}`}>
    <polyline points="6 9 12 15 18 9"/>
  </svg>);
// ChevronRight
export const ChevronRight = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-chevron-right ${className}`}>
    <polyline points="9 18 15 12 9 6"/>
  </svg>);
// Search
export const Search = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-search ${className}`}>
    <circle cx="11" cy="11" r="8"/>
    <path d="m21 21-4.35-4.35"/>
  </svg>);
// X
export const X = ({ className = '', size = 24 }) => (<svg xmlns="http://www.w3.org/2000/svg" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={`lucide lucide-x ${className}`}>
    <line x1="18" y1="6" x2="6" y2="18"/>
    <line x1="6" y1="6" x2="18" y2="18"/>
  </svg>);
//# sourceMappingURL=lucide-react.js.map