import { LightningElement } from 'lwc';
import getRequests from '@salesforce/apex/LeaveRequestController.getRequests';

export default class LeaveRequestList extends LightningElement {
    rows = [];
    statusFilter = 'All';
    searchKey = '';
    loading = false;

    statusOptions = ['All', 'Pending', 'Approved', 'Rejected'].map((v) => ({
        label: v,
        value: v
    }));

    columns = [
        { label: 'ID', fieldName: 'Name' },
        { label: 'Employee', fieldName: 'employee' },
        { label: 'Type', fieldName: 'Leave_Type__c' },
        { label: 'Start', fieldName: 'Start_Date__c', type: 'date' },
        { label: 'End', fieldName: 'End_Date__c', type: 'date' },
        { label: 'Days', fieldName: 'Duration__c', type: 'number' },
        { label: 'Status', fieldName: 'Status__c' },
        { label: 'Manager Comments', fieldName: 'Manager_Comments__c' }
    ];

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const data = await getRequests({ status: this.statusFilter });
            this.rows = data.map((r) => ({
                ...r,
                employee: r.Employee__r ? r.Employee__r.Name : ''
            }));
        } catch (error) {
            this.rows = [];
        } finally {
            this.loading = false;
        }
    }

    handleStatus(event) {
        this.statusFilter = event.detail.value;
        this.load();
    }

    handleSearch(event) {
        this.searchKey = event.target.value.toLowerCase();
    }

    get filtered() {
        if (!this.searchKey) return this.rows;
        return this.rows.filter((r) =>
            [r.Name, r.employee, r.Leave_Type__c, r.Reason__c].some(
                (v) => v && v.toLowerCase().includes(this.searchKey)
            )
        );
    }

    get hasRows() {
        return this.filtered.length > 0;
    }
}