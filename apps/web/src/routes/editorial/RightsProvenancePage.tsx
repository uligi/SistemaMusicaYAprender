import { CreditProvenancePage } from './CreditProvenancePage';
import { RightsAdministrationPanel } from './RightsAdministrationPanel';

export type RightsProvenancePageProps = {
  recordingId: string;
};

export function RightsProvenancePage({ recordingId }: RightsProvenancePageProps) {
  return (
    <>
      <CreditProvenancePage recordingId={recordingId} />
      <RightsAdministrationPanel recordingId={recordingId} />
    </>
  );
}
