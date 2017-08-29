import ModalFunctionality from 'discourse/mixins/modal-functionality';
import { ajax } from 'discourse/lib/ajax';
import { on, observes, default as computed } from 'ember-addons/ember-computed-decorators';
import User from 'discourse/models/user';

export default Ember.Controller.extend(ModalFunctionality, {
  nominationSaveDisabled: Ember.computed.or('nominationsUnchanged', 'savingNominations'),
  selfNominationSaveDisabled: Ember.computed.or('selfNominationUnchanged', 'savingSelfNomination'),
  savingNominations: false,
  savingSelfNomination: false,
  savedNominations: null,
  savedSelfNomination: null,
  usernames: null,
  showSelector: false,

  @observes('model')
  setup() {
    this.clear();

    const model = this.get('model');
    if (model) {
      this.setProperties({
        usernames: model.nomineeUsernames.join(','),
        showSelector: true,
        selfNominationAllowed: model.selfNominationAllowed == 'true'
      })
    }
  },

  @computed('usernames', 'model.nomineeUsernames')
  nominationsUnchanged(usernames, nomineeUsernames) {
    if (typeof usernames === 'string') {
      usernames = usernames.split(',');
    };

    let unchanged = true;

    if (usernames.length !== nomineeUsernames.length) {
      unchanged = false;
    }

    for (let i = 0; i < usernames.length; i++) {
      if (nomineeUsernames.indexOf(usernames[i]) === -1) {
        unchanged = false;
      }
    }

    if (!unchanged) {
      this.set('savedNominations', null);
    }

    return unchanged;
  },

  @computed('selfNominationAllowed', 'model.selfNominationAllowed')
  selfNominationUnchanged(allowed, original) {
    if (typeof original === 'string') {
      original = original == 'true';
    }

    let unchanged = allowed == original;

    if (!unchanged) {
      this.set('savedSelfNomination', null);
    }

    return unchanged;
  },

  resolve(result, property) {
    if (result.failed) {
      this.set(`saved${property}`, 'times');
      this.flash(result.message, 'error');
    } else {
      this.set(`saved${property}`, 'check');
    }
    this.set(`saving${property}`, false);
  },

  clear() {
    this.setProperties({
      savedNominations: null,
      savedSelfNomination: null
    })
  },

  actions: {
    close() {
      this.clear();
      this.send('closeModal');
    },

    saveNominations() {
      if (this.get('nominationSaveDisabled')) return;

      const topicId = this.get('model.topicId');
      const usernames = this.get('usernames').split(',');

      this.set('savingNominations', true);

      ajax('/election/nominations', {
        type: 'POST',
        data: {
          topic_id: topicId,
          usernames
        }
      }).then((result) => {
        this.resolve(result, 'Nominations');

        if (result.failed) {
          const existing = this.get('model.nomineeUsernames');
          this.set('usernames', existing.join(','));

          // this is hack to get around stack overflow issues with user-selector's canReceiveUpdates property
          this.set('showSelector', false);
          Ember.run.scheduleOnce('afterRender', this, () => this.set('showSelector', true));
        } else {
          this.set('model.nomineeUsernames', usernames);
        }
      })
    },

    saveSelfNomination() {
      const topicId = this.get('model.topicId');
      const selfNominationAllowed = this.get('selfNominationAllowed');

      this.set('savingSelfNomination', true);

      ajax('/election/nomination/self', {
        type: 'PUT',
        data: {
          topic_id: topicId,
          state: selfNominationAllowed
        }
      }).then((result) => {
        this.resolve(result, 'SelfNomination');

        if (result.error_message) {
          this.set('selfNominationAllowed', !selfNominationAllowed);
        } else {
          this.set('model.selfNominationAllowed', selfNominationAllowed);
        }
      })
    }
  }
})
