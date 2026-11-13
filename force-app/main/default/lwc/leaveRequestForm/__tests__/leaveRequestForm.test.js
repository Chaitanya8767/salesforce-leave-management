import { createElement } from '@lwc/engine-dom';
import LeaveRequestForm from 'c/leaveRequestForm';
import saveRequest from '@salesforce/apex/LeaveRequestController.saveRequest';
const TOAST_EVENT_NAME = 'lightning__showtoast';

jest.mock(
    '@salesforce/apex/LeaveRequestController.saveRequest',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

// YYYY-MM-DD for "today + offsetDays" in local time (same rule the component uses)
const isoDate = (offsetDays) => {
    const d = new Date();
    d.setDate(d.getDate() + offsetDays);
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${d.getFullYear()}-${month}-${day}`;
};

// Fill a field the same way a user would: set the value, fire "change".
const setField = (element, field, value) => {
    const input = element.shadowRoot.querySelector(`[data-field="${field}"]`);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
};

const fillForm = (element, { type = 'Sick', start, end, reason = 'Fever' }) => {
    setField(element, 'leaveType', type);
    setField(element, 'startDate', start);
    setField(element, 'endDate', end);
    setField(element, 'reason', reason);
};

const createForm = () => {
    const element = createElement('c-leave-request-form', { is: LeaveRequestForm });
    document.body.appendChild(element);
    return element;
};

describe('c-leave-request-form', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the form with initial state and default duration text', () => {
        const element = createForm();

        const card = element.shadowRoot.querySelector('lightning-card');
        expect(card).not.toBeNull();
        expect(card.title).toBe('Apply for Leave');

        const durationP = element.shadowRoot.querySelector('p');
        expect(durationP.textContent).toContain('-');
    });

    it('calculates duration correctly when valid dates are entered', async () => {
        const element = createForm();

        setField(element, 'startDate', isoDate(1));
        setField(element, 'endDate', isoDate(3));
        await Promise.resolve();

        const durationP = element.shadowRoot.querySelector('p');
        expect(durationP.textContent).toContain('3 day(s)');
    });

    it('displays invalid date range if end date is earlier than start date', async () => {
        const element = createForm();

        setField(element, 'startDate', isoDate(3));
        setField(element, 'endDate', isoDate(1));
        await Promise.resolve();

        const durationP = element.shadowRoot.querySelector('p');
        expect(durationP.textContent).toContain('Invalid date range');
    });

    it('shows an error toast and does not save when a field is empty', async () => {
        const element = createForm();
        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        fillForm(element, { start: isoDate(1), end: isoDate(2), reason: '' });
        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(saveRequest).not.toHaveBeenCalled();
        expect(toastHandler).toHaveBeenCalledTimes(1);
        expect(toastHandler.mock.calls[0][0].detail.title).toBe('Missing data');
    });

    it('rejects a start date in the past without calling Apex', async () => {
        const element = createForm();
        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        fillForm(element, { start: isoDate(-2), end: isoDate(-1) });
        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(saveRequest).not.toHaveBeenCalled();
        const detail = toastHandler.mock.calls[0][0].detail;
        expect(detail.title).toBe('Invalid dates');
        expect(detail.message).toBe('Start date cannot be in the past.');
    });

    it('calls Apex and shows a success toast for a valid request', async () => {
        saveRequest.mockResolvedValue({ Id: 'a00000000000001' });
        const element = createForm();
        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        const start = isoDate(1);
        const end = isoDate(2);
        fillForm(element, { type: 'Casual', start, end, reason: 'Family event' });
        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(saveRequest).toHaveBeenCalledWith({
            leaveType: 'Casual',
            startDate: start,
            endDate: end,
            reason: 'Family event'
        });
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('success');
    });

    it('shows the server error message when Apex rejects the request', async () => {
        saveRequest.mockRejectedValue({
            body: { message: 'You already have a Pending or Approved leave request that overlaps these dates.' }
        });
        const element = createForm();
        const toastHandler = jest.fn();
        element.addEventListener(TOAST_EVENT_NAME, toastHandler);

        fillForm(element, { start: isoDate(1), end: isoDate(2) });
        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        const detail = toastHandler.mock.calls[0][0].detail;
        expect(detail.variant).toBe('error');
        expect(detail.message).toContain('overlaps');
    });
});
