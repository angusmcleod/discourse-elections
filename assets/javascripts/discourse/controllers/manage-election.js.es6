import ModalFunctionality from 'discourse/mixins/modal-functionality';
import { ElectionStatuses } from '../lib/election';
import { observes, default as computed } from 'ember-addons/ember-computed-decorators';

export default Ember.Controller.extend(ModalFunctionality, {
  showSelector: false,
  nominationParam: { type: 'nomination' },
  pollParam: { type: 'poll' },

  @observes('model')
  setup() {
    const model = this.get('model');
    if (model) {
      const topic = model.topic;

      this.setProperties({
        showSelector: true,
        topic: model.topic,
        position: topic.election_position,
        usernamesString: topic.election_nominations_usernames.join(','),
        selfNomination: topic.election_self_nomination_allowed,
        statusBanner: topic.election_status_banner,
        statusBannerResultHours: topic.election_status_banner_result_hours,
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

  @computed('position')
  positionInvalid(position) {
    return !position || position.length < 3;
  },

  actions: {
    close() {
      this.send('closeModal');
    },

    error(message) {
      this.flash(message, 'error');
    },

    saved() {
      this.get('model.rerender')();
    }
  }
});
