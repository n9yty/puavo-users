
import React from "react";
import R from "ramda";
import {connect} from "react-redux";

import t from "../i18n";
import {GENERATE_USERNAME} from "../constants";
import ColumnTypes from "../ColumnTypes";

import PureComponent from "./PureComponent";

class Username extends PureComponent {
    render() {
        const {schoolId, username} = this.props;
        return (
            <a href={`/users/${schoolId}/username_redirect/${username}`}>{username}</a>
        );
    }
}
Username.propTypes = {
    username: React.PropTypes.string.isRequired,
    schoolId: React.PropTypes.number.isRequired,
};
Username = connect(state => ({schoolId: R.path(["defaultSchool", "id"], state)}))(Username);


class UsernameInput extends PureComponent {
    render() {
        const generate = this.props.value === GENERATE_USERNAME;

        return (
            <span>
                <input
                    type="text"
                    onChange={this.props.onChange}
                    disabled={generate} />
                <label style={{fontSize: "small"}}>
                    <input
                        type="checkbox"
                        disabled={!this.props.canGenerateUsername}
                        onChange={_ => {
                            if (generate) {
                                this.props.onChange({target: {value: ""}});
                            } else {
                                this.props.onChange({target: {value: GENERATE_USERNAME}});
                            }
                        }}
                        checked={generate}
                    />
                    {t("generate_username")}
                </label>
                {!this.props.canGenerateUsername &&
                <p style={{fontSize: "small", fontStyle: "italic"}}>
                    {t("add_names_to_generate_username")}
                </p>}
            </span>
        );

    }
}
UsernameInput.propTypes = {
    value: React.PropTypes.string.isRequired,
    onChange: React.PropTypes.func.isRequired,
    canGenerateUsername: React.PropTypes.bool.isRequired,
};


const isFirstName = R.equals(ColumnTypes.first_name);
const isLastName = R.equals(ColumnTypes.last_name);
const canGenerateUsername = R.allPass(R.map(R.any, [isFirstName, isLastName]));

UsernameInput = connect(state => {
    return {canGenerateUsername: canGenerateUsername(state.columns)};
})(UsernameInput);


export {Username, UsernameInput};