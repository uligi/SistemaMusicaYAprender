import { AccessProvider } from './access/AccessContext';
import { AppRouter } from './router/AppRouter';

export function App() {
  return (
    <AccessProvider>
      <AppRouter />
    </AccessProvider>
  );
}
