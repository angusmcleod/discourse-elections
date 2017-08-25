import { createWidget } from 'discourse/widgets/widget';
import showModal from 'discourse/lib/show-modal';
import { ajax } from 'discourse/lib/ajax';
import { h } from 'virtual-dom';

export default createWidget('election-controls', {
  tagName: 'div.election-controls',
  buildKey: (attrs) => `election-controls`,

  defaultState(attrs) {
    let nominations = attrs.topic.election_nominations;
    let isNominated = false;

    if (nominations && nominations.length) {
      nominations = nominations.split('|') || [];
      isNominated = nominations && nominations.indexOf(this.currentUser.username) > -1;
    }

    return {
      nominations,
      isNominated,
      startingElection: false
    }
  },

  toggleNomination() {
    const topic = this.attrs.topic;
    const categoryId = topic.category_id;
    const topicId = topic.id;
    const position = topic.election_position;
    const isNominated = this.state.isNominated;

    showModal('nomination-confirmation', {
      model: {
        isNominated,
        categoryId,
        topicId,
        position,
        callback: () => {
          this.state.isNominated = !this.state.isNominated;
          this.scheduleRerender();
        }
      }
    });
  },

  manageNominees() {
    const topic = this.attrs.topic;
    const usernames = this.state.nominations;
    const topicId = topic.id;

    showModal('nomination-manage', {
      model: {
        topicId,
        usernames,
        callback: (usernames) => {
          this.state.nominations = usernames;
          this.scheduleRerender();
        }
      }
    });
  },

  startElection() {
    const topicId = this.attrs.topic.id;

    ajax('/election/start', {type: 'PUT', data: { topic_id: topicId}}).then((result) => {
      if (result.failed) {
        bootbox.alert(result.message);
      }

      this.state.startingElection = false;
      this.scheduleRerender();
    })

    this.state.startingElection = true;
    this.scheduleRerender();
  },

  html(attrs, state) {
    const topic = attrs.topic;
    const user = this.currentUser;
    let contents = [];

    if (topic.election_status === 'nominate' && topic.election_self_nomination_allowed === "true") {
      contents.push(this.attach('button', {
        action: `toggleNomination`,
        label: `election.nomination.${state.isNominated ? 'remove.label' : 'add.label'}`,
        className: 'btn btn-primary'
      }))
    }

    if (user.is_elections_admin && topic.election_status === 'nominate') {
      contents.push(this.attach('button', {
        action: 'manageNominees',
        label: 'election.nomination.manage.label',
        className: 'btn btn-primary'
      }))

      contents.push(this.attach('button', {
        action: 'startElection',
        label: 'election.start',
        className: 'btn btn-primary'
      }))

      if (state.startingElection) {
        contents.push(h('div.spinner-container', h('div.spinner.small')))
      }
    }

    return contents;
  }
})
