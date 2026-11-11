import React from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

class AppErrorBoundary extends React.Component {
  constructor(props) { super(props); this.state = { error: null }; }
  static getDerivedStateFromError(error) { return { error }; }
  componentDidCatch(error, info) { console.error('[Watch Ads & Earn] UI crashed', error, info); }
  render() {
    if (this.state.error) return <main style={{minHeight:'100vh',background:'#090909',color:'#f7f4ef',display:'grid',placeContent:'center',padding:24,fontFamily:'Arial,sans-serif'}}>
      <section style={{maxWidth:520}}>
        <div style={{color:'#ffad28',fontWeight:800,letterSpacing:2}}>WATCH ADS & EARN</div>
        <h1 style={{fontSize:28}}>We hit a loading problem</h1>
        <p style={{color:'#bbb',lineHeight:1.6}}>The page encountered an error. Your account and points have not been changed. Please reload the page. If it happens again, send this error message to support.</p>
        <pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere',background:'#191919',padding:14,borderRadius:8,color:'#ffc15b',fontSize:12}}>{String(this.state.error?.message || this.state.error)}</pre>
        <button onClick={()=>window.location.reload()} style={{background:'#f5a623',border:0,borderRadius:9,padding:'13px 20px',fontWeight:800}}>Reload page</button>
      </section>
    </main>;
    return this.props.children;
  }
}

window.addEventListener('error', event => console.error('[Watch Ads & Earn] Window error:', event.error || event.message));
window.addEventListener('unhandledrejection', event => console.error('[Watch Ads & Earn] Promise error:', event.reason));

createRoot(document.getElementById('root')).render(
  <React.StrictMode><AppErrorBoundary><App/></AppErrorBoundary></React.StrictMode>
);
