import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import isManager from '@salesforce/apex/LeaveRequestController.isManager';
import getRequests from '@salesforce/apex/LeaveRequestController.getRequests';
import updateStatus from '@salesforce/apex/LeaveRequestController.updateStatus';

export default class LeaveApproval extends LightningElement {
    rows = [];
    selectedId;
    comments = '';

    @wire(isManager) isManager;

    columns = [
        { label: 'ID', fieldName: 'Name' },
        { label: 'Employee', fieldName: 'employee' },
        { label: 'Type', fieldName: 'Leave_Type__c' },
        { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
        { label: 'End', fieldName: 'End_Date__c', type: 'date' },
        { label: 'Days', fieldName: 'Duration__c', type: 'number' },
        { label: 'Reason', fieldName: 'Reason__c' }
    ];

    connectedCallback() {
        this.load();
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    async load() {
        try {
            const data = await getRequests({ status: 'Pending' });
            this.rows = data.map((r) => ({
                ...r,
                employee: r.Employee__r ? r.Employee__r.Name : ''
            }));
        } catch (error) {
            this.rows = [];
        }
        this.selectedId = null;
    }

    handleSelect(event) {
        const selected = event.detail.selectedRows;
        this.selectedId = selected.length ? selected[0].Id : null;
    }

    handleComments(event) {
        this.comments = event.target.value;
    }

    approve() {
        this.decide('Approved');
    }

    reject() {
        this.decide('Rejected');
    }

    async decide(status) {
        if (!this.selectedId) {
            this.showToast('Select a request', 'Pick a row first.', 'warning');
            return;
        }
        if (status === 'Rejected' && !this.comments) {
            this.showToast('Comment required', 'Please add a comment when rejecting.', 'warning');
            return;
        }
        try {
            await updateStatus({
                requestId: this.selectedId,
                status: status,
                comments: this.comments
            });
            this.showToast('Done', `Request ${status.toLowerCase()}.`, 'success');
            this.comments = '';
            await this.load();
        } catch (error) {
            const msg = error.body ? error.body.message : error.message;
            this.showToast('Error', msg, 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}