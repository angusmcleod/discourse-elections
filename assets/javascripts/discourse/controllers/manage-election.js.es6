import ModalFunctionality from 'discourse/mixins/modal-functionality';
import { ElectionStatuses } from '../lib/election';
import { ajax } from 'discourse/lib/ajax';
import { on, observes, default as computed } from 'ember-addons/ember-computed-decorators';
import User from 'discourse/models/user';
import { extractError } from 'discourse/lib/ajax-error';

export default Ember.Controller.extend(ModalFunctionality, {
  nominationsDisabled: Ember.computed.or('nominationsUnchanged', 'nominationsSaving'),
  selfNominationDisabled: Ember.computed.or('selfNominationUnchanged', 'selfNominationSaving'),
  statusDisabled: Ember.computed.or('statusUnchanged', 'statusSaving'),
  doneDisabled: Ember.computed.or('nominationsSaving', 'selfNominationSaving', 'statusSaving'),
  nominationsSaving: false,
  selfNominationSaving: false,
  statusSaving: false,
  nominationsIcon: null,
  selfNominationIcon: null,
  statusIcon: null,
  usernames: null,
  showSelector: false,

  @observes('model')
  setup() {
    this.clear();

    const model = this.get('model');
    if (model) {
      this.setProperties({
        usernames: model.nominations.join(','),
        showSelector: true,
        selfNomination: model.selfNomination == 'true',
        status: model.status
      })
    }
  },

  @computed()
  electionStatuses() {
    return Object.keys(ElectionStatuses).map(function(k, i){
      return {
        name: k,
        id: ElectionStatuses[k]
      }
    })
  },

  @computed('usernames')
  nominations() {
    return this.get('usernames').split(',');
  },

  @computed('nominations', 'model.nominations')
  nominationsUnchanged(newNominations, currentNominations) {
    let unchanged = true;

    if (newNominations.length !== currentNominations.length) {
      unchanged = false;
    }

    for (let i = 0; i < newNominations.length; i++) {
      if (currentNominations.indexOf(newNominations[i]) === -1) {
        unchanged = false;
      }
    }

    return unchanged;
  },

  @computed('status', 'model.status')
  statusUnchanged(current, original) {
    return current == original;
  },

  @computed('selfNomination', 'model.selfNomination')
  selfNominationUnchanged(current, original) {
    if (typeof original === 'string') {
      original = original == 'true';
    }

    return current == original;
  },

  resolve(result, type) {
    if (result.failed) {
      this.set(`${type}Icon`, 'times');
      this.flash(result.message, 'error');
    } else {
      this.set(`${type}Icon`, 'check');
    }
    this.set(`${type}Saving`, false);
  },

  clear() {
    this.setProperties({
      nominationsIcon: null,
      selfNominationIcon: null,
      statusIcon: null
    })
  },

  prepare(type) {
    if (this.get(`${type}SaveDisabled`)) return false;
    this.set(`${type}Saving`, true);

    $('#modal-alert').hide();

    const topicId = this.get('model.topicId');
    let data = { topic_id: topicId};

    data[type] = this.get(type);

    return data;
  },

  actions: {
    close() {
      this.clear();
      this.send('closeModal');
    },

    statusSave() {
      const data = this.prepare('status');
      if (!data) return;

      ajax('/election/set-status', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'status');

        if (result.failed) {
          const existing = this.get('model.status');
          this.set('status', existing);
        } else {
          this.set('model.status', data['status']);
          this.get('model.setTopicStatus')(data['status']);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          let message = e.jqXHR.responseText.substring(0, e.jqXHR.responseText.indexOf('----'));
          this.resolve({ failed: true, message })
        }
      })
    },

    nominationsSave() {
      const data = this.prepare('nominations');
      if (!data) return;

      ajax('/election/nominations', { type: 'POST', data }).then((result) => {
        this.resolve(result, 'nominations');

        if (result.failed) {
          const existing = this.get('model.nominations');
          this.set('usernames', existing.join(','));

          // this is hack to get around stack overflow issues with user-selector's canReceiveUpdates property
          this.set('showSelector', false);
          Ember.run.scheduleOnce('afterRender', this, () => this.set('showSelector', true));
        } else {
          this.set('model.nominations', data['nominations']);
        }
      })
    },

    selfNominationSave() {
      const data = this.prepare('selfNomination');
      if (!data) return;

      ajax('/election/nomination/self', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'selfNomination');

        if (result.error_message) {
          this.set('selfNomination', !data['selfNomination']);
        } else {
          this.set('model.selfNomination', data['selfNomination']);
        }
      })
    }
  }
})
