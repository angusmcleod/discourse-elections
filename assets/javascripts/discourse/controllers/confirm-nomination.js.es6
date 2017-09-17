import { default as computed } from 'ember-addons/ember-computed-decorators';
import ModalFunctionality from 'discourse/mixins/modal-functionality';
import Category from 'discourse/models/category';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend(ModalFunctionality, {
  @computed('model.topic.election_is_nominee')
  prefix(isNominee) {
    return `election.nomination.${isNominee ? 'remove' : 'add'}.`;
  },

  @computed('model.topic.category_id')
  categoryName(categoryId) {
    return Category.findById(categoryId).name;
  },

  actions: {
    toggleNomination() {
      const topicId = this.get('model.topic.id');
      const isNominee = this.get('model.topic.election_is_nominee');
      const type = isNominee ? 'DELETE' : 'POST';

      this.set('loading', true);
      ajax('/election/nomination', {
        type,
        data: {
          topic_id: topicId
        }
      }).then((result) => {
        if (result.failed) {
          this.flash(result.message, 'error');
        } else {
          const user = this.currentUser;
          let nominations = this.get('model.topic.election_nominations');
          let usernames = this.get('model.topic.election_nominations_usernames');

          if (isNominee) {
            usernames.splice(usernames.indexOf(user.username), 1);
            nominations.splice(nominations.indexOf(user.id), 1);
          } else {
            usernames.push(user.username);
            nominations.push(user.id);
          }

          this.set('model.topic.election_nominations_usernames', usernames);
          this.set('model.topic.election_nominations', nominations);
          this.set('model.topic.election_is_nominee', !isNominee);
          this.get('model.rerender')();
          this.send('closeModal');
        }

        this.set('loading', false);
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          const responseText = e.jqXHR.responseText;
          const message = responseText.substring(responseText.indexOf('>') + 1, responseText.indexOf('plugins'));
          bootbox.alert(message);
        }
      });
    }
  }
});
