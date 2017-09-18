import ModalFunctionality from 'discourse/mixins/modal-functionality';
import { ElectionStatuses } from '../lib/election';
import { ajax } from 'discourse/lib/ajax';
import { observes, default as computed } from 'ember-addons/ember-computed-decorators';

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
        selfNomination: topic.election_self_nomination_allowed,
        status: topic.election_status,
        nominationMessage: topic.election_nomination_message,
        pollMessage: topic.election_poll_message,
        sameMessage: topic.same_message
      });
    }
  },

  @computed()
  electionStatuses() {
    return Object.keys(ElectionStatuses).map(function(k){
      return {
        name: k,
        id: ElectionStatuses[k]
      };
    });
  },

  @computed('usernamesString')
  usernames(usernamesString) {
    return usernamesString.split(',');
  },

  @computed('usernames', 'topic.election_nominations_usernames')
  usernamesUnchanged(newUsernames, currentUsernames) {
    let unchanged = true;

    // ensure there are no empty strings
    newUsernames = newUsernames.filter(Boolean);
    currentUsernames = currentUsernames.filter(Boolean);

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
    return Number(current) === Number(original);
  },

  @computed('selfNomination', 'topic.election_self_nomination_allowed')
  selfNominationUnchanged(current, original) {
    return current === original;
  },

  @computed('nominationMessage', 'topic.election_nomination_message')
  nominationMessageUnchanged(current, original) {
    return current === original;
  },

  @computed('pollMessage', 'topic.election_poll_message')
  pollMessageUnchanged(current, original) {
    return current === original;
  },

  @computed('position', 'topic.election_position')
  positionUnchanged(current, original) {
    return current === original;
  },

  @computed('position')
  positionInvalid(position) {
    return !position || position.length < 3;
  },

  resolve(result, type) {
    if (result.success) {
      this.set(`${type}Icon`, 'check');

    } else if (result.failed) {
      this.set(`${type}Icon`, 'times');
      this.flash(result.message, 'error');

    } else {
      setTimeout(() => {
        this.set(`${type}Icon`, null);
      }, 5000);
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
    });
  },

  prepare(type, serializedType, opts) {
    if (this.get(`${type}SaveDisabled`)) return false;

    this.clearIcons();
    this.set(`${type}Saving`, true);
    $('#modal-alert').hide();

    const topicId = this.get('topic.id');
    let data = { topic_id: topicId};

    data[serializedType] = this.get(type);

    Object.assign(data, opts);

    return data;
  },

  resolveStandardError(responseText, property) {
    const message = responseText.substring(responseText.indexOf('>'), responseText.indexOf('----'));
    this.resolve({ failed: true, message }, property);
  },

  actions: {
    close() {
      this.clearIcons();
      this.send('closeModal');
    },

    positionSave() {
      const data = this.prepare('position', 'position');
      if (!data) return;

      ajax('/election/set-position', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'position');

        if (result.failed) {
          this.set('position', this.get('topic.election_position'));
        } else {
          this.set('topic.election_position', data['position']);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          this.resolveStandardError(e.jqXHR.responseText, 'position');
          this.set('position', this.get('topic.election_position'));
        }
      }).finally(() => this.resolve({}, 'position'));
    },

    statusSave() {
      const data = this.prepare('status', 'status');
      if (!data) return;

      ajax('/election/set-status', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'status');

        if (result.failed) {
          this.set('status', this.get('topic.election_status'));
        } else {
          this.set('topic.election_status', result.status);
          this.get('model.rerender')();
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          this.resolveStandardError(e.jqXHR.responseText, 'status');
          this.set('status', this.get('topic.election_status'));
        }
      }).finally(() => this.resolve({}, 'status'));
    },

    usernamesSave() {
      const data = this.prepare('usernames', 'usernames');
      if (!data) return;

      const handleFail = () => {
        const existing = this.get('topic.election_nominations_usernames');
        this.set('usernamesString', existing.join(','));

        // this is hack to get around stack overflow issues with user-selector's canReceiveUpdates property
        this.set('showSelector', false);
        Ember.run.scheduleOnce('afterRender', this, () => this.set('showSelector', true));
      };

      ajax('/election/nomination/set-by-username', { type: 'POST', data }).then((result) => {
        this.resolve(result, 'usernames');

        if (result.failed) {
          handleFail();
        } else {
          this.set('topic.election_nominations', result.user_ids);
          this.set('topic.election_nominations_usernames', result.usernames);
          this.set('topic.election_is_nominee', result.user_ids.indexOf(this.currentUser.id) > -1);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          this.resolveStandardError(e.jqXHR.responseText, 'usernames');
          handleFail();
        }
      }).finally(() => this.resolve({}, 'usernames'));
    },

    selfNominationSave() {
      const data = this.prepare('selfNomination', 'state');
      if (!data) return;

      ajax('/election/set-self-nomination', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'selfNomination');

        if (result.failed) {
          this.set('selfNomination', !data['selfNomination']);
        } else {
          this.set('topic.election_self_nomination_allowed', result.state);
          this.get('model.rerender')();
        }
      }).finally(() => this.resolve({}, 'selfNomination'));
    },

    nominationMessageSave() {
      const data = this.prepare('nominationMessage', 'message', { type: 'nomination' });
      if (!data) return;

      ajax('/election/set-message', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'nominationMessage');

        if (result.failed) {
          this.set('nominationMessage', this.get('topic.election_nomination_message'));
        } else {
          this.set('topic.election_nomination_message', data['message']);
        }
      }).finally(() => this.resolve({}, 'nominationMessage'));
    },

    pollMessageSave() {
      const data = this.prepare('pollMessage', 'message', { type: 'poll' });
      if (!data) return;

      ajax('/election/set-message', { type: 'PUT', data }).then((result) => {
        this.resolve(result, 'pollMessage');

        if (result.failed) {
          this.set('pollMessage', this.get('topic.election_poll_message'));
        } else {
          this.set('topic.election_poll_message', data['message']);
        }
      }).finally(() => this.resolve({}, 'pollMessage'));
    }
  }
});
