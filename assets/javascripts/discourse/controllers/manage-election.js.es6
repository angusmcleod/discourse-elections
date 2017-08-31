import ModalFunctionality from 'discourse/mixins/modal-functionality';
import { ElectionStatuses } from '../lib/election';
import { ajax } from 'discourse/lib/ajax';
import { on, observes, default as computed } from 'ember-addons/ember-computed-decorators';
import User from 'discourse/models/user';
import { extractError } from 'discourse/lib/ajax-error';

export default Ember.Controller.extend(ModalFunctionality, {
  usernamesDisabled: Ember.computed.or('usernamesUnchanged', 'usernamesSaving'),
  selfNominationDisabled: Ember.computed.or('selfNominationUnchanged', 'selfNominationSaving'),
  statusDisabled: Ember.computed.or('statusUnchanged', 'statusSaving'),
  nominationMessageDisabled: Ember.computed.or('nominationMessageUnchanged', 'nominationMessageSaving'),
  pollMessageDisabled: Ember.computed.or('pollMessageUnchanged', 'pollMessageSaving'),
  positionDisabled: Ember.computed.or('positionUnchanged', 'positionSaving', 'positionInvalid'),
  doneDisabled: Ember.computed.or('positionSaving', 'usernamesSaving', 'selfNominationSaving', 'statusSaving', 'nominationMessageSaving', 'pollMessageSaving'),
  usernamesSaving: false,
  selfNominationSaving: false,
  statusSaving: false,
  nominationMessageSaving: false,
  pollMessageSaving: false,
  positionSaving: false,
  usernamesIcon: null,
  selfNominationIcon: null,
  statusIcon: null,
  nominationMessageIcon: null,
  pollMessageIcon: null,
  positionIcon: null,
  showSelector: false,

  @observes('model')
  setup() {
    this.clearIcons();

    const model = this.get('model');
    if (model) {
      const topic = model.topic;

      this.setProperties({
        showSelector: true,
        topic: model.topic,
        position: topic.election_position,
        usernamesString: topic.election_nominations_usernames.join(','),
        selfNomination: topic.election_self_nomination_allowed == 'true',
        status: topic.election_status,
        nominationMessage: topic.election_nomination_message,
        pollMessage: topic.election_poll_message,
        sameMessage: topic.same_message
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

  @computed('usernamesString')
  usernames(usernamesString) {
    return usernamesString.split(',');
  },

  @computed('usernames', 'topic.election_nominations_usernames')
  usernamesUnchanged(newUsernames, currentUsernames) {
    let unchanged = true;

    if (newUsernames.length !== currentUsernames.length) {
      unchanged = false;
    }

    for (let i = 0; i < newUsernames.length; i++) {
      if (currentUsernames.indexOf(newUsernames[i]) === -1) {
        unchanged = false;
      }
    }

    return unchanged;
  },

  @computed('status', 'topic.election_status')
  statusUnchanged(current, original) {
    return current == original;
  },

  @computed('selfNomination', 'topic.election_self_nomination_allowed')
  selfNominationUnchanged(current, original) {
    if (typeof original === 'string') {
      original = original == 'true';
    }

    return current == original;
  },

  @computed('nominationMessage', 'topic.election_nomination_message')
  nominationMessageUnchanged(current, original) {
    return current == original;
  },

  @computed('pollMessage', 'topic.election_poll_message')
  pollMessageUnchanged(current, original) {
    return current == original;
  },

  @computed('position', 'topic.election_position')
  positionUnchanged(current, original) {
    return current == original;
  },

  @computed('position')
  positionInvalid(position) {
    return !position || position.length < 3;
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

  clearIcons() {
    this.setProperties({
      usernamesIcon: null,
      selfNominationIcon: null,
      statusIcon: null,
      nominationMessageIcon: null,
      pollMessageIcon: null,
      positionIcon: null
    })
  },

  prepare(type) {
    if (this.get(`${type}SaveDisabled`)) return false;

    this.clearIcons();
    this.set(`${type}Saving`, true);
    $('#modal-alert').hide();

    const topicId = this.get('topic.id');
    let data = { topic_id: topicId};

    let serialized_type = type.replace(/[A-Z]/g, "_$&").toLowerCase();
    data[serialized_type] = this.get(type);

    return data;
  },

  actions: {
    close() {
      this.clearIcons();
      this.send('closeModal');
    },

    positionSave() {
      const data = this.prepare('position');
      if (!data) return;

      ajax('/election/set-position', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'position');

        if (result.failed) {
          this.set('existing', this.get('topic.election_position'));
        } else {
          this.set('topic.election_position', data['position']);
        }
      })
    },

    statusSave() {
      const data = this.prepare('status');
      if (!data) return;

      ajax('/election/set-status', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'status');

        if (result.failed) {
          this.set('status', this.get('topic.election_status'));
        } else {
          this.set('topic.election_status', data['status']);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          let message = e.jqXHR.responseText.substring(0, e.jqXHR.responseText.indexOf('----'));
          this.resolve({ failed: true, message })
        }
      })
    },

    usernamesSave() {
      const data = this.prepare('usernames');
      if (!data) return;

      ajax('/election/nomination/set-by-username', { type: 'POST', data }).then((result) => {
        this.resolve(result, 'usernames');

        if (result.failed) {
          const existing = this.get('topic.election_nominations_usernames');
          this.set('usernames', existing.join(','));

          // this is hack to get around stack overflow issues with user-selector's canReceiveUpdates property
          this.set('showSelector', false);
          Ember.run.scheduleOnce('afterRender', this, () => this.set('showSelector', true));
        } else {
          this.set('topic.election_nominations_usernames', data['usernames']);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          let message = e.jqXHR.responseText.substring(0, e.jqXHR.responseText.indexOf('----'));
          this.resolve({ failed: true, message })
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
          this.set('topic.election_self_nomination_allowed', data['self_nomination']);
        }
      })
    },

    nominationMessageSave() {
      const data = this.prepare('nominationMessage');
      if (!data) return;

      ajax('/election/set-nomination-message', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'nominationMessage');

        if (result.error_message) {
          this.set('nominationMessage', this.get('topic.election_nomination_message'));
        } else {
          this.set('topic.election_nomination_message', data['nomination_message'])
        }
      })
    },

    pollMessageSave() {
      const data = this.prepare('pollMessage');
      if (!data) return;

      ajax('/election/set-poll-message', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'pollMessage');

        if (result.error_message) {
          this.set('pollMessage', this.get('topic.election_poll_message'));
        } else {
          this.set('topic.election_poll_message', data['poll_message'])
        }
      })
    }
  }
})
