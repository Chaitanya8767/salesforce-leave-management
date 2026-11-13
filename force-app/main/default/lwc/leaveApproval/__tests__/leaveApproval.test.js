import { createElement } from '@lwc/engine-dom';
import LeaveApproval from 'c/leaveApproval';
import isManager from '@salesforce/apex/LeaveRequestController.isManager';
import getRequests from '@salesforce/apex/LeaveRequestController.getRequests';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';

jest.mock(
    '@salesforce/apex/LeaveRequestController.getRequests',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const isManagerWireAdapter = registerApexTestWireAdapter(isManager);

describe('c-leave-approval', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('displays restriction message when user is not a manager', async () => {
        getRequests.mockResolvedValue([]);

        const element = createElement('c-leave-approval', {
            is: LeaveApproval
        });
        document.body.appendChild(element);

        isManagerWireAdapter.emit(false);

        await Promise.resolve();

        const restrictionP = element.shadowRoot.querySelector('p');
        expect(restrictionP).not.toBeNull();
        expect(restrictionP.textContent).toBe('Only managers can view this section.');
    });

    it('renders card title and empty pending message when user is a manager', async () => {
        getRequests.mockResolvedValue([]);

        const element = createElement('c-leave-approval', {
            is: LeaveApproval
        });
        document.body.appendChild(element);

        isManagerWireAdapter.emit(true);

        await Promise.resolve();
        await Promise.resolve();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Pending Approvals');

        const noPendingP = element.shadowRoot.querySelector('p');
        expect(noPendingP).not.toBeNull();
        expect(noPendingP.textContent).toBe('No pending requests.');
    });
});
