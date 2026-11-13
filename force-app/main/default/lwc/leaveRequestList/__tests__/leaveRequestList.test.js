import { createElement } from '@lwc/engine-dom';
import LeaveRequestList from 'c/leaveRequestList';
import getRequests from '@salesforce/apex/LeaveRequestController.getRequests';

jest.mock(
    '@salesforce/apex/LeaveRequestController.getRequests',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

describe('c-leave-request-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders card title and status combobox', async () => {
        getRequests.mockResolvedValue([]);

        const element = createElement('c-leave-request-list', {
            is: LeaveRequestList
        });
        document.body.appendChild(element);

        await Promise.resolve();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Leave Requests');

        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
        expect(combobox.options.length).toBe(4);
    });

    it('displays fallback message when no leave requests exist', async () => {
        getRequests.mockResolvedValue([]);

        const element = createElement('c-leave-request-list', {
            is: LeaveRequestList
        });
        document.body.appendChild(element);

        await Promise.resolve();

        const noRowsP = element.shadowRoot.querySelector('p.slds-m-top_medium');
        expect(noRowsP).not.toBeNull();
        expect(noRowsP.textContent).toBe('No leave requests found.');
    });

    it('displays error message block when load fails', async () => {
        getRequests.mockRejectedValue({ body: { message: 'Failed to load records.' } });

        const element = createElement('c-leave-request-list', {
            is: LeaveRequestList
        });
        document.body.appendChild(element);

        await Promise.resolve();
        await Promise.resolve();

        const errorP = element.shadowRoot.querySelector('p.slds-text-color_error');
        expect(errorP).not.toBeNull();
        expect(errorP.textContent).toBe('Failed to load records.');
    });

    it('filters the table by search text', async () => {
        getRequests.mockResolvedValue([
            { Id: '1', Name: 'LR-0001', Leave_Type__c: 'Sick', Reason__c: 'Fever', Employee__r: { Name: 'Asha' } },
            { Id: '2', Name: 'LR-0002', Leave_Type__c: 'Casual', Reason__c: 'Trip', Employee__r: { Name: 'Ravi' } }
        ]);

        const element = createElement('c-leave-request-list', {
            is: LeaveRequestList
        });
        document.body.appendChild(element);
        await Promise.resolve();
        await Promise.resolve();

        let table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table.data.length).toBe(2);

        const search = element.shadowRoot.querySelector('lightning-input');
        search.value = 'ravi';
        search.dispatchEvent(new CustomEvent('change'));
        await Promise.resolve();

        table = element.shadowRoot.querySelector('lightning-datatable');
        expect(table.data.length).toBe(1);
        expect(table.data[0].Name).toBe('LR-0002');
    });
});
