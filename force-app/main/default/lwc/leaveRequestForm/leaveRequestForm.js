import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, MessageContext } from 'lightning/messageService';
import LEAVE_CHANNEL from '@salesforce/messageChannel/LeaveRequestChannel__c';
import saveRequest from '@salesforce/apex/LeaveRequestController.saveRequest';

export default class LeaveRequestForm extends LightningElement {
    leaveType = '';
    startDate = '';
    endDate = '';
    reason = '';

    @wire(MessageContext) messageContext;

    typeOptions = [
        { label: 'Sick', value: 'Sick' },
        { label: 'Casual', value: 'Casual' },
        { label: 'Earned', value: 'Earned' }
    ];

    handleChange(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    // Today's date as YYYY-MM-DD in the user's local time zone.
    get today() {
        const d = new Date();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${month}-${day}`;
    }

    get endMinDate() {
        return this.startDate || this.today;
    }

    get duration() {
        if (!this.startDate || !this.endDate) return null;
        const days = (new Date(this.endDate) - new Date(this.startDate)) / 86400000 + 1;
        return days > 0 ? days : null;
    }

    get durationText() {
        if (!this.startDate || !this.endDate) return '-';
        return this.duration ? `${this.duration} day(s)` : 'Invalid date range';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    async handleSubmit() {
        if (!this.leaveType || !this.startDate || !this.endDate || !this.reason?.trim()) {
            this.showToast('Missing data', 'Please fill all fields.', 'error');
            return;
        }
        if (!this.duration) {
            this.showToast('Invalid dates', 'End date cannot be before start date.', 'error');
            return;
        }
        if (this.startDate < this.today) {
            this.showToast('Invalid dates', 'Start date cannot be in the past.', 'error');
            return;
        }
        try {
            await saveRequest({
                leaveType: this.leaveType,
                startDate: this.startDate,
                endDate: this.endDate,
                reason: this.reason
            });
            this.showToast('Success', 'Leave request submitted.', 'success');
            this.leaveType = '';
            this.startDate = '';
            this.endDate = '';
            this.reason = '';
            // Tell the list and approval panel to refresh themselves.
            publish(this.messageContext, LEAVE_CHANNEL, { source: 'form' });
        } catch (error) {
            const msg = error.body ? error.body.message : error.message;
            this.showToast('Error', msg, 'error');
        }
    }
}
